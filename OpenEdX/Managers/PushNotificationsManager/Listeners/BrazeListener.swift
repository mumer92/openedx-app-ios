//
//  BrazeListener.swift
//  OpenEdX
//
//  Created by Anton Yarmolenka on 24/01/2024.
//

import Foundation

class BrazeListener: PushNotificationsListener {
    func notificationToThisListener(userinfo: [AnyHashable: Any]) -> Bool { false }
}
