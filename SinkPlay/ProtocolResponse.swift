//
//  ProtocolResponse.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2023-03-09.
//

import Foundation

enum ProtocolResponse: Codable {
    case error(Error)
    case chat(Chat)
    // annoying these optional values could be an enum of their own... need to figure out best way for that
    // other values: controllerAuth, newControlledRoom, room
    case set(Set)
    case state(State)
    case list([String: [String: ListUser]])
    case hello(Hello)
    
    struct Error: Codable {
        let message: String
    }
    
    struct Chat: Codable {
        let username: String
        let message: String
    }
    
    struct Hello: Codable {
        let username: String
        let room: Room
        let version: String
        let realversion: String
        let features: [String: Feature]
        let motd: String
    }
    
    // State can have multiple entries
    struct State: Codable {
        let ping: Ping
        let playstate: PlayState
        let ignoringOnTheFly: IgnoringOnTheFly?
    }
    
    // Set doesn't seem to, but the Python implementation treats it like it does, so no enum here
    struct Set: Codable {
        let playlistChange: PlaylistChange?
        let playlistIndex: PlaylistIndex?
        let ready: Ready?
        let user: [String: User]?
    }
    
    struct ListUser: Codable {
        let position: Double
        let controller: Bool
        let isReady: Bool
        let file: File? // represented as an empty object {}
        let features: [String: Feature]
        
        enum CodingKeys: String, CodingKey {
            case position, controller, isReady, file, features
        }
        
        // sadly, we need to do this for File (i woud rather not make the keys on File nullable, until we have to...)
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.position = try container.decode(Double.self, forKey: .position)
            self.isReady = try container.decode(Bool.self, forKey: .isReady)
            self.controller = try container.decode(Bool.self, forKey: .controller)
            self.features = try container.decode([String: Feature].self, forKey: .features)
            // it is OK if this fails
            self.file = try? container.decode(File.self, forKey: .file)
        }
    }
    
    enum Feature: Codable {
        case int(Int)
        case bool(Bool)
        case string(String)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                throw DecodingError.typeMismatch(Feature.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Feature"))
            }
        }
    }
    
    struct Room: Codable {
        let name: String
    }
    
    struct Ping: Codable {
        let latencyCalculation: Double
        let clientLatencyCalculation: Double?
        let serverRtt: Double
    }
    
    struct PlayState: Codable {
        let position: Double
        let paused: Bool
        let doSeek: Bool? // should really be Bool
        let setBy: String?
    }
    
    struct IgnoringOnTheFly: Codable {
        let server: Int?
    }
    
    struct File: Codable {
        // some of these are optionals...
        let name: String
        let duration: String // convert to a double later
        let size: UInt64
    }
    
    struct User: Codable {
        let room: Room
        let event: Event?
        let file: File?
        
        /*
        struct Event: Codable {
            let joined: Bool?
            let features: [String: Feature]?
            let version: String?
            
            let left: Bool?
        }
         */
        enum Event: Codable {
            case joined//(version: String?, features: [String: Feature]?)
            case left
            
            enum CodingKeys: String, CodingKey {
                // TODO: How do we put the keys needed for version/features here?
                case joined, left//, version, features
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if (try? container.decode(Bool.self, forKey: .joined)) == true {
                    //let version = try? container.decode(String.self, forKey: .version)
                    //self = .joined(version: "", features: [:])
                    self = .joined
                } else if (try? container.decode(Bool.self, forKey: .left)) == true {
                    self = .left
                } else {
                    throw DecodingError.typeMismatch(Event.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Event"))
                }
            }
        }
    }
    
    struct PlaylistChange: Codable {
        let user: String?
        let files: [File] // XXX
    }
    
    struct PlaylistIndex: Codable {
        let user: String?
        let index: Int? // another dumb case
        
        enum CodingKeys: String, CodingKey {
            case user, index
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.user = try? container.decode(String.self, forKey: .user)
            if let x = try? container.decode(Int.self, forKey: .index) {
                self.index = x
            } else if (try? container.decode(String.self, forKey: .index)) != nil {
                self.index = nil // as the stirng indicates null somehow
            } else if try container.decodeNil(forKey: .index) {
                self.index = nil
            } else {
                throw DecodingError.typeMismatch(PlaylistIndex.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for PlaylistIndex.index"))
            }
        }
    }
    
    struct Ready: Codable {
        let isReady: Bool // either "<null>" or 0/1. awful, but we can fix that.
        let manuallyInitiated: Bool?
        let username: String
        
        enum CodingKeys: String, CodingKey {
            case isReady, manuallyInitiated, username
        }
        
        // manual because of isReady...
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.username = try! container.decode(String.self, forKey: .username)
            self.manuallyInitiated = try? container.decode(Bool.self, forKey: .manuallyInitiated)
            // now handle either case
            if let x = try? container.decode(Bool.self, forKey: .isReady) {
                self.isReady = x
            } else if (try? container.decode(String.self, forKey: .isReady)) != nil {
                self.isReady = false // as the string indicates null
            } else if try container.decodeNil(forKey: .isReady) {
                self.isReady = false
            } else {
                throw DecodingError.typeMismatch(Ready.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Ready.isReady"))
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case chat = "Chat"
        case hello = "Hello"
        case set = "Set"
        case state = "State"
        case list = "List"
    }
    
    // sad
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let error = try? container.decode(Error.self, forKey: .error) {
            self = .error(error)
        } else if let chat = try? container.decode(Chat.self, forKey: .chat) {
            self = .chat(chat)
        } else if let hello = try? container.decode(Hello.self, forKey: .hello) {
            self = .hello(hello)
        } else if let set = try? container.decode(Set.self, forKey: .set) {
            self = .set(set)
        } else if let state = try? container.decode(State.self, forKey: .state) {
            self = .state(state)
        } else if let list = try? container.decode([String: [String: ListUser]].self, forKey: .list) {
            self = .list(list)
        } else {
            throw DecodingError.typeMismatch(ProtocolResponse.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for ProtocolResponse"))
        }
    }
}
