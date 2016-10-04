//
//  MessageFetchingOperation.swift
//
//  Created by Andrey K. on 20/06/16.
//

import Foundation
import CoreData

final class MessageFetchingOperation: Operation {
	var context: NSManagedObjectContext
	var finishBlock: ((MMFetchMessagesResult) -> Void)?
	var remoteAPIQueue: MMRemoteAPIQueue
	var result = MMFetchMessagesResult.Cancel
	
	init(context: NSManagedObjectContext, remoteAPIQueue: MMRemoteAPIQueue, finishBlock: ((MMFetchMessagesResult) -> Void)? = nil) {
		self.context = context
		self.remoteAPIQueue = remoteAPIQueue
		self.finishBlock = finishBlock
		
		super.init()
		
		self.addCondition(RegistrationCondition(internalId: MobileMessaging.currentUser?.internalId))
	}
	
	override func execute() {
		MMLogDebug("Starting message fetching operation...")
		self.syncMessages()
	}
	
	private func syncMessages() {
		self.context.performAndWait {
			guard let internalId = MobileMessaging.currentUser?.internalId else
			{
				self.finishWithError(NSError(type: MMInternalErrorType.NoRegistration))
				return
			}
			
			let date = NSDate(timeIntervalSinceNow: -60 * 60 * 24 * 7) // consider messages not older than 7 days
			let fetchLimit = 100 // consider 100 most recent messages
			let nonReportedMessages = MessageManagedObject.MM_findAllWithPredicate(NSPredicate(format: "reportSent == false"), context: self.context)
			let archivedMessages = MessageManagedObject.MM_find(withPredicate: NSPredicate(format: "reportSent == true && creationDate > %@", date), fetchLimit: fetchLimit, sortedBy: "creationDate", ascending: false, inContext: self.context)
			
			let nonReportedMessageIds = nonReportedMessages?.map{ $0.messageId }
			let archveMessageIds = archivedMessages?.map{ $0.messageId }
			
			let request = MMPostSyncRequest(internalId: internalId, archiveMsgIds: archveMessageIds, dlrMsgIds: nonReportedMessageIds)
			MMLogDebug("Found \(nonReportedMessageIds?.count) not reported messages. \(archivedMessages?.count) archive messages.")

			self.remoteAPIQueue.perform(request: request) { result in
				self.handleRequestResponse(result: result, nonReportedMessageIds: nonReportedMessageIds)
			}
		}
	}

	private func handleRequestResponse(result: MMFetchMessagesResult, nonReportedMessageIds: [String]?) {
		self.result = result
		
		self.context.performAndWait {
			switch result {
			case .Success(let fetchResponse):
				let fetchedMessages = fetchResponse.messages
				MMLogDebug("Messages fetching succeded: received \(fetchedMessages?.count) new messages: \(fetchedMessages)")
				
				if let nonReportedMessageIds = nonReportedMessageIds {
					self.dequeueDeliveryReports(messageIDs: nonReportedMessageIds)
					MMLogDebug("Delivery report sent for messages: \(nonReportedMessageIds)")
					if nonReportedMessageIds.count > 0 {
						NotificationCenter.mm_postNotificationFromMainThread(name: MMNotificationDeliveryReportSent, userInfo: [MMNotificationKeyDLRMessageIDs: nonReportedMessageIds])
					}
				}
				
			case .Failure(_):
				MMLogError("Sync request failed")
			case .Cancel:
				MMLogDebug("Sync cancelled")
				break
			}
			self.finishWithError(result.error as NSError?)
		}
	}
	
	private func dequeueDeliveryReports(messageIDs: [String]) {
		guard let messages = MessageManagedObject.MM_findAllWithPredicate(NSPredicate(format: "messageId IN %@", messageIDs), context: context)
			, messages.count > 0
			else
		{
			return
		}
		
		messages.forEach { message in
			message.reportSent = true
		}
		
		MMLogDebug("Marked as delivered: \(messages.map{ $0.messageId })")
		context.MM_saveToPersistentStoreAndWait()
		
		self.updateMessageStorage(with: messages)
	}
	
	private func updateMessageStorage(with messages: [MessageManagedObject]) {
		messages.forEach({ MobileMessaging.sharedInstance?.messageStorageAdapter?.update(deliveryReportStatus: $0.reportSent , for: $0.messageId) })
	}
	
	private func handleMessageOperation(messages: [MTMessage]) -> MessageHandlingOperation {
		return MessageHandlingOperation(messagesToHandle: messages,
		                                messagesDeliveryMethod: .pull,
		                                context: self.context,
		                                remoteAPIQueue: self.remoteAPIQueue,
		                                messageHandler: MobileMessaging.messageHandling) { error in
											
											var finalResult = self.result
											if let error = error {
												finalResult = MMFetchMessagesResult.Failure(error)
											}
											self.finishBlock?(finalResult)
		}
	}
	
	override func finished(_ errors: [NSError]) {
		MMLogDebug("Message fetching operation finished with errors: \(errors)")
		let finishResult = errors.isEmpty ? result : MMFetchMessagesResult.Failure(errors.first)
		switch finishResult {
		case .Success(let fetchResponse):
			if let messages = fetchResponse.messages , messages.count > 0 {
				self.produceOperation(handleMessageOperation(messages: messages))
			} else {
				self.finishBlock?(result)
			}
		default:
			self.finishBlock?(result)
		}
	}
}