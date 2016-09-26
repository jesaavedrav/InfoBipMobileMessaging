//
//  MessageManagedObject.swift
//  
//
//  Created by Andrey K. on 24/02/16.
//
//

import Foundation
import CoreData

enum MMSeenStatus : Int32 {
    case NotSeen = 0
    case SeenNotSent
    case SeenSent
}

enum MMMessageType : Int32 {
	case Default = 0
	case Geo
}

final class MessageManagedObject: NSManagedObject {
	override func MM_awakeFromCreation() {
		self.creationDate = NSDate()
	}
    var seenStatus: MMSeenStatus {
		get { return MMSeenStatus(rawValue: seenStatusValue.intValue) ?? .NotSeen }
		set { seenStatusValue = NSNumber(int: newValue.rawValue) }
    }
	var messageType: MMMessageType {
		get { return MMMessageType(rawValue: messageTypeValue.intValue) ?? .Default }
		set { messageTypeValue = NSNumber(int: newValue.rawValue) }
	}
}
