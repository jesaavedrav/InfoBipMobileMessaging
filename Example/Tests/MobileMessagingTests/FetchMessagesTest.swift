//
//  SyncMessagesTest.swift
//  MobileMessaging
//
//  Created by okoroleva on 21.03.16.
//

import XCTest

@testable import MobileMessaging

struct SyncTestAppIds {
    static let kCorrectIdNothingToSynchronize = "CorrectIdNothingToSynchronize"
    static let kCorrectIdMergeSynchronization = "CorrectIdMergeSynchronization"
}

class FetchMessagesTest: MMTestCase {
    /**Conditions:
    1. Empty DB
    2. synchronization request was sent
    3. empty mIds response received
     
     Expected result:
     nothing changed in DB
    */
    func testNothingToSynchronize() {
		cleanUpAndStop()
		startWithApplicationCode(SyncTestAppIds.kCorrectIdNothingToSynchronize)
		
		weak var expectation = self.expectation(description: "Sync finished")
        XCTAssertEqual(self.nonReportedStoredMessagesCount(self.storage.mainThreadManagedObjectContext!), 0, "There must be not any stored message")
                
        let messageHandler = mobileMessagingInstance.messageHandler
		
		mobileMessagingInstance.currentUser.internalId = MMTestConstants.kTestCorrectInternalID
		
		messageHandler.syncWithServer { error in
			
			XCTAssertNil(error)
			XCTAssertEqual(self.nonReportedStoredMessagesCount(self.storage.mainThreadManagedObjectContext!), 0, "There must be not any stored message")
			expectation?.fulfill()
        }
        
        waitForExpectations(timeout: 60, handler: nil)
    }
	
	/**
	Preconditions:
	1. m2(new message) is in DB
	Actions:
	1. new message m1 received
	2. sync
	Expectations:
	m2 seen and deivered, m1 delivered
	*/
	func testConcurrency() {
		weak var prepconditionExpectation = expectation(description: "Initial message base set up")
		weak var seenExpectation = expectation(description: "Seen request finished")
		weak var syncExpectation = expectation(description: "Sync finished")
		weak var newMsgExpectation = expectation(description: "New message received")

		cleanUpAndStop()
		startWithApplicationCode(SyncTestAppIds.kCorrectIdMergeSynchronization)
		
		//Precondiotions
		mobileMessagingInstance.currentUser.internalId = MMTestConstants.kTestCorrectInternalID
		mobileMessagingInstance.didReceiveRemoteNotification(["aps": ["key":"value"], "messageId": "m2"], newMessageReceivedCallback: nil, completion: { error in
			prepconditionExpectation?.fulfill()
		})
		
		//Actions
		mobileMessagingInstance.setSeen(["m2"], completion: { result in
			seenExpectation?.fulfill()
		})
		
		mobileMessagingInstance.didReceiveRemoteNotification(["aps": ["key":"value"], "messageId": "m1"], newMessageReceivedCallback: nil, completion: { error in
			newMsgExpectation?.fulfill()
		})

		mobileMessagingInstance.messageHandler.syncWithServer({ error in
			syncExpectation?.fulfill()
		})
		
		//Expectations
		waitForExpectations(timeout: 60) { error in
			let ctx = self.storage.mainThreadManagedObjectContext!
			ctx.reset()
			ctx.performAndWait {
				if let messages = MessageManagedObject.MM_findAllInContext(ctx) {
					let m1 = messages.filter({$0.messageId == "m1"}).first
					let m2 = messages.filter({$0.messageId == "m2"}).first
					XCTAssertEqual(m2?.seenStatus, MMSeenStatus.SeenSent, "m2 must be seen and synced")
					XCTAssertEqual(m2?.reportSent, true, "m2 delivery report must be delivered")
					XCTAssertEqual(m1?.seenStatus, MMSeenStatus.NotSeen, "m1 must be not seen")
					XCTAssertEqual(m1?.reportSent, true, "m1 delivery report must be delivered")
				} else {
					XCTFail("There should be some messages in database")
				}
			}
		}
	}
}

class MessageHandlingMock : MMDefaultMessageHandling {
	let localNotificationShownBlock: (Void) -> Void
	init(localNotificationShownBlock: @escaping (Void) -> Void) {
		self.localNotificationShownBlock = localNotificationShownBlock
	}
	override func presentLocalNotificationAlert(with message: MTMessage) {
		self.localNotificationShownBlock()
	}
}
