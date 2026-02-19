// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

public struct Empty: Sendable {
    public struct Message: Codable, Sendable {}
}

public struct Key: Sendable {
    public typealias NodePublic = String
}

public struct IP: Sendable {
    public typealias Addr = String
    public typealias Prefix = String
}

public struct Time: Sendable {
    public typealias Time = String
}

public struct Ipn: Sendable {
    public enum State: Int, Codable, CaseIterable, Sendable {
        case NoState = 0
        case InUseOtherUser = 1
        case NeedsLogin = 2
        case NeedsMachineAuth = 3
        case Stopped = 4
        case Starting = 5
        case Running = 6
    }

    public struct EngineStatus: Codable, Sendable, Equatable {
        public var RBytes: Int64
        public var WBytes: Int64
        public var NumLive: Int
        public var LivePeers: [Key.NodePublic: IpnState.PeerStatusLite]
    }

    public struct Notify: Codable, Sendable {
        public var Version: String?
        public var SessionID: String?
        public var ErrMessage: String?
        public var LoginFinished: Empty.Message?
        public var State: State?
        public var Prefs: Prefs?
        public var NetMap: Netmap.NetworkMap?
        public var Engine: EngineStatus?
        public var BrowseToURL: String?
        public var LocalTCPPort: UInt16?
        public var ClientVersion: Tailcfg.ClientVersion?
    }

    public struct NotifyWatchOpt: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let engineUpdates    = NotifyWatchOpt(rawValue: 1 << 0)
        public static let initialState     = NotifyWatchOpt(rawValue: 1 << 1)
        public static let prefs            = NotifyWatchOpt(rawValue: 1 << 2)
        public static let netmap           = NotifyWatchOpt(rawValue: 1 << 3)
        public static let noPrivateKeys    = NotifyWatchOpt(rawValue: 1 << 4)
        public static let rateLimitNetmaps = NotifyWatchOpt(rawValue: 1 << 8)
    }

    public struct Prefs: Codable, Sendable {
        public var ControlURL: String = ""
        public var RouteAll: Bool = false
        public var AllowSingleHosts: Bool = false
        public var CorpDNS: Bool = false
        public var WantRunning: Bool = false
        public var LoggedOut: Bool = false
        public var ShieldsUp: Bool = false
        public var AdvertiseRoutes: [String]?
        public var AdvertiseTags: [String]?
        public var ExitNodeID: Tailcfg.StableNodeID = ""
        public var ExitNodeAllowLANAccess: Bool = false
        public var ForceDaemon: Bool? = false
        public var Hostname: String = ""
    }

    public struct MaskedPrefs: Codable, Sendable {
        public var ControlURL: String = "" {didSet {
            ControlURLSet = true
        }}
        public var RouteAll: Bool = false {didSet {
            RouteAllSet = true
        }}
        public var CorpDNS: Bool = false {didSet {
            CorpDNSSet = true
        }}
        public var ExitNodeID: String = "" {didSet {
            ExitNodeIDSet = true
        }}
        public var ExitNodeAllowLANAccess: Bool = false {didSet {
            ExitNodeAllowLANAccessSet = true
        }}
        public var WantRunning: Bool = false {didSet {
            WantRunningSet = true
        }}
        public var ShieldsUp: Bool = false {didSet {
            ShieldsUpSet = true
        }}
        public var AdvertiseRoutes: [String]? {didSet {
            AdvertiseRoutesSet = true
        }}
        public var ForceDaemon: Bool = false {didSet {
            ForceDaemonSet = true
        }}
        public var Hostname: String = "" {didSet {
            HostnameSet = true
        }}

        // Mask fields should not need to be manually set, they are automatically
        // populated in setters.
        private(set) var ControlURLSet: Bool?
        private(set) var RouteAllSet: Bool?
        private(set) var CorpDNSSet: Bool?
        private(set) var ExitNodeIDSet: Bool?
        private(set) var ExitNodeAllowLANAccessSet: Bool?
        private(set) var WantRunningSet: Bool?
        private(set) var ShieldsUpSet: Bool?
        private(set) var AdvertiseRoutesSet: Bool?
        private(set) var ForceDaemonSet: Bool?
        private(set) var HostnameSet: Bool?

        public init() {}

        // Helper builder functions which can be chained in place of the convenience
        // initializer.
        @discardableResult
        public func controlURL(_ value: String) -> MaskedPrefs {
            var p = self
            p.ControlURL = value
            return p
        }

        @discardableResult
        public func routeAll(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.RouteAll = value
            return p
        }

        @discardableResult
        public func corpDNS(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.CorpDNS = value
            return p
        }

        @discardableResult
        public func exitNodeID(_ value: String) -> MaskedPrefs {
            var p = self
            p.ExitNodeID = value
            return p
        }

        @discardableResult
        public func exitNodeAllowLANAccess(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.ExitNodeAllowLANAccess = value
            return p
        }

        @discardableResult
        public func wantRunning(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.WantRunning = value
            return p
        }

        @discardableResult
        public func shieldsUp(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.ShieldsUp = value
            return p
        }

        @discardableResult
        public func advertiseRoutes(_ value: [String]) -> MaskedPrefs {
            var p = self
            p.AdvertiseRoutes = value
            return p
        }

        @discardableResult
        public func forceDaemon(_ value: Bool) -> MaskedPrefs {
            var p = self
            p.ForceDaemon = value
            return p
        }

        @discardableResult
        public func hostname(_ value: String) -> MaskedPrefs {
            var p = self
            p.Hostname = value
            return p
        }
    }

    public struct Options: Codable {
        public var UpdatePrefs: Prefs?
        public var AuthKey: String?
    }
}

public struct IpnLocal: Sendable {
    public struct LoginProfile: Equatable, Codable, Identifiable, Sendable {
        public var ID: String
        public var Name: String
        public var Key: String
        public var UserProfile: Tailcfg.UserProfile
        public var NetworkProfile: Tailcfg.NetworkProfile?
        public var LocalUserID: String
        public var ControlURL: String?
        public var id: String { self.ID }

        public func isNullUser() -> Bool {
            return id.isEmpty
        }
    }
}

public struct IpnState: Sendable {
    public struct PeerStatus: Codable, Equatable, Sendable {
        public var ID: Tailcfg.StableNodeID
        public var HostName: String
        public var DNSName: String
        public var TailscaleIPs: [IP.Addr]?
        public var Tags: [String]?
        public var PrimaryRoutes: [String]?
        public var Addrs: [String]?
        public var CurAddr: String?
        public var Relay: String?
        public var PeerRelay: String?
        public var Online: Bool
        public var ExitNode: Bool
        public var ExitNodeOption: Bool
        public var PeerAPIURL: [String]?
        public var Capabilities: [String]?
        public var SSH_HostKeys: [String]?
        public var ShareeNode: Bool?
        public var Expired: Bool?
    }

    public  struct PeerStatusLite: Codable, Sendable, Equatable {
        public var RxBytes: Int64
        public var TxBytes: Int64
        public var LastHandshake: Time.Time
        public var NodeKey: String
    }

    public struct Status: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case Version,
                 BackendState,
                 AuthURL,
                 TailscaleIPs,
                 ExitNodeStatus,
                 Health,
                 CurrentTailnet,
                 CertDomains,
                 Peer,
                 User,
                 ClientVersion
            case SelfStatus = "Self"
        }

        public var Version: String
        public var BackendState: String
        public var AuthURL: String
        public var TailscaleIPs: [IP.Addr]?
        public var SelfStatus: PeerStatus?
        public var ExitNodeStatus: ExitNodeStatus?
        public var Health: [String]?
        public var CurrentTailnet: TailnetStatus?
        public var CertDomains: [String]?
        public var Peer: [String: PeerStatus]?
        public var User: [String: Tailcfg.UserProfile]?
        public var ClientVersion: Tailcfg.ClientVersion?
    }

    public struct ExitNodeStatus: Codable, Sendable {
        public var ID: Tailcfg.StableNodeID
        public var Online: Bool
        public var TailscaleIPs: [IP.Prefix]?
    }

    public struct TailnetStatus: Codable, Sendable {
        public var Name: String
        public var MagicDNSSuffix: String
        public var MagicDNSEnabled: Bool
    }

    struct PingResult: Codable, Sendable {
        public var IP: IP.Addr
        public var Err: String
        public var LatencySeconds: TimeInterval
    }
}

public struct Netmap: Sendable {
    public struct NetworkMap: Codable, Equatable, Sendable {
        public var SelfNode: Tailcfg.Node
        public var NodeKey: Key.NodePublic
        public var Peers: [Tailcfg.Node]?
        public var Domain: String
        public var UserProfiles: [String: Tailcfg.UserProfile] // Keys are tailcfg.UserIDs thet get stringified
        public var DNS: Tailcfg.DNSConfig?

        public func currentUserProfile() -> Tailcfg.UserProfile? {
            return userProfile(for: SelfNode.User)
        }

        public func userProfile(for id: Int64) -> Tailcfg.UserProfile? {
            return UserProfiles[String(id)]
        }

        public static func == (lhs: Netmap.NetworkMap, rhs: Netmap.NetworkMap) -> Bool {
            lhs.SelfNode == rhs.SelfNode &&
            lhs.NodeKey == rhs.NodeKey &&
            lhs.Peers == rhs.Peers &&
            lhs.Domain == rhs.Domain &&
            lhs.UserProfiles == rhs.UserProfiles &&
            lhs.DNS == rhs.DNS
        }
    }
}

public struct Tailcfg: Sendable {
    public typealias MachineKey = String
    public typealias NodeID = Int64
    public typealias StableNodeID = String
    public typealias UserID = Int64

    public struct Hostinfo: Codable, Equatable, Sendable {
        public var OS: String?
        public var OSVersion: String?
        public var DeviceModel: String?
        public var ShareeNode: Bool?
        public var Hostname: String?
        public var ShieldsUp: Bool?
    }

    public struct Node: Codable, Equatable, @unchecked Sendable {
        public var ID: Tailcfg.NodeID
        public var StableID: Tailcfg.StableNodeID
        public var Name: String
        public var User: Tailcfg.UserID
        public var Sharer: Tailcfg.UserID?
        public var Key: Key.NodePublic
        public var KeyExpiry: Time.Time?
        public var Addresses: [IP.Prefix]?
        public var AllowedIPs: [IP.Prefix]?
        public var Hostinfo: Hostinfo
        public var LastSeen: Time.Time?
        public var Online: Bool?
        public var Capabilities: [String]?
        public var Tags: [String]?

        public var ComputedName: String
        public var ComputedNameWithHost: String

        // reports whether Node offers default routing services.
        public var IsExitNode: Bool {
            var default4: Bool = false
            var default6: Bool = false
            for ip in self.AllowedIPs ?? [] {
                if ip == "0.0.0.0/0" {
                    default4 = true
                } else if ip == "::/0" {
                    default6 = true
                }
                if default4 && default6 {
                    return true
                }
            }
            return false
        }

        public var isAdmin: Bool {
            return !(self.Capabilities ?? []).filter({ $0 == "https://tailscale.com/cap/is-admin" }).isEmpty
        }

        public var KeyDoesNotExpire: Bool {
            if KeyExpiry == GoZeroTimeString {
                return true
            }
            return false
        }

        public var HasExpiredAuth: Bool {
            if KeyDoesNotExpire {
                return false
            }

            if let expiryDate = KeyExpiry?.iso8601Date() {
                return (expiryDate as NSDate).earlierDate(Date()) == expiryDate && !KeyDoesNotExpire
            }

            return false
        }

        /// Returns the UserId of the user who owns this node. That's either the user who shared this node
        /// with the current user if available, or the actual owner of the node.
        public var SharerOrUser: Tailcfg.UserID {
            Sharer ?? User
        }

        public var hasNonZeroLastSeen: Bool {
            LastSeen != GoZeroTimeString
        }

        public static func == (lhs: Tailcfg.Node, rhs: Tailcfg.Node) -> Bool {
            lhs.ID == rhs.ID &&
            lhs.Name == rhs.Name &&
            lhs.Online == rhs.Online &&
            lhs.IsExitNode == rhs.IsExitNode &&
            lhs.KeyExpiry == rhs.KeyExpiry &&
            lhs.Addresses == rhs.Addresses &&
            lhs.Capabilities == rhs.Capabilities
        }
    }

    public struct UserProfile: Equatable, Codable, Identifiable, Hashable, Sendable {
        public var ID: Int64
        public var DisplayName: String
        public var LoginName: String
        public var ProfilePicURL: String?
        public var id: Int64 { self.ID }
        public var isTaggedDevice: Bool { LoginName == "tagged-devices" }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    public struct NetworkProfile: Codable, Equatable, Sendable {
        public var MagicDNSName: String?
        public var DomainName: String?
        public var DisplayName: String?
    }

    public struct DNSRecord: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case Name
            case RecordType = "Type"
            case Value
        }

        public var Name: String
        public var RecordType: String?
        public var Value: String
    }

    public struct DNSConfig: Codable, Sendable, Equatable {
        public var Resolvers: [DNSType.Resolver]?
        public var Routes: [String: [DNSType.Resolver]?]?
        public var FallbackResolvers: [DNSType.Resolver]?
        public var Domains: [String]?
        public var Nameservers: [IP.Addr]?
        public var ExtraRecords: [DNSRecord]?
    }

    public struct ClientVersion: Codable, Sendable, Equatable {
        public var RunningLatest: Bool?
        public var LatestVersion: String?
        public var UrgentSecurityUpdate: Bool?
        public var Notify: Bool?
        public var NotifyURL: String?
        public var NotifyText: String?
    }
}

public struct DNSType: Sendable {
    public struct Resolver: Codable, Identifiable, Sendable, Equatable {
        public var Addr: String?
        public var BootstrapResolution: [IP.Addr]?
        public var id: String { Addr ?? "" }
    }
}

struct GoError: Codable, Sendable, LocalizedError {
    let Error: String

    init(error: String) {
        self.Error = error
    }

    var errorDescription: String? {
        return Error
    }
}

