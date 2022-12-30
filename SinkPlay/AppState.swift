//
//  AppState.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-28.
//

import Foundation
import SwiftUI

class AppState : ObservableObject {
    // variables and such
    @Published var currentURL: URL?
    
    @Published var server: String?
    @Published var port: Int32 = 8999
    @Published var nick: String?
    @Published var room: String?
    @Published var pass: String?
    
    // current state (connecion)
    
    func connect(server: String, port: Int32, nick: String, room: String, pass: String) {
        
    }
}
