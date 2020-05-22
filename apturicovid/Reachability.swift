//
//  Reachability.swift
//  apturicovid
//
//  Created by Artjoms Spole on 21/05/2020.
//  Copyright © 2020 MAK IT. All rights reserved.
//

import SystemConfiguration
import CFNetwork
import Foundation

public enum ReachabilityError: Error {
    case failedToCreateWithAddress(sockaddr, Int32)
    case failedToCreateWithHostname(String, Int32)
    case unableToSetCallback(Int32)
    case unableToSetDispatchQueue(Int32)
    case unableToGetFlags(Int32)
}

struct ReachabilityGroup {
    var apiConnection: Reachability.Connection?
    var networkConnection: Reachability.Connection
}

class Reachability {
    
    static let shared: Reachability? = try? Reachability(domainName: nil)
    
    var allowsCellularConnection = true

    private let reachabilityRef: SCNetworkReachability
    private let reachabilitySerialQueue = DispatchQueue.init(label: "reachability", qos: .default)
    private let notificationQueue = DispatchQueue.main
    
    private (set) var notifierRunning = false
    
    private (set) var flags: SCNetworkReachabilityFlags? {
        didSet { if flags != oldValue { notifyReachabilityChanged() } }
    }
    
    var apiConnection: Connection {
        if flags == nil { try? setReachabilityFlags() }
        
        switch flags?.connection {
        case .unavailable?, nil: return .unavailable
        case .none?: return .unavailable
        case .cellular?: return allowsCellularConnection ? .cellular : .unavailable
        case .wifi?: return .wifi
        }
    }
    
    /// Run when app launches. This will initialize shared instance
    func begin(){}
    
    deinit { stopNotifier() }
    
    /// - Parameter domainName: domain name to track. Use nil in case track global network connectivity
    required init(domainName: String?) throws {
        
        if let domainName = domainName,
            let ipAddress = Reachability.resolvedIpAddress(fromDomainName: domainName),
            let ref = SCNetworkReachabilityCreateWithName(nil, ipAddress){
            reachabilityRef = ref
        } else {
            var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
            zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
            zeroAddress.sin_family = sa_family_t(AF_INET)
            
            let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                    SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
                }
            }
            
            guard let ref = defaultRouteReachability else {
                throw ReachabilityError.failedToCreateWithHostname(domainName ?? "127.0.0.1", SCError())
            }
            reachabilityRef = ref
        }

        try startNotifier()
    }
    
    func setReachabilityFlags() throws {
        try reachabilitySerialQueue.sync { [unowned self] in
            var flags = SCNetworkReachabilityFlags()
            if !SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags) {
                self.stopNotifier()
                throw ReachabilityError.unableToGetFlags(SCError())
            }
            self.flags = flags
        }
    }
    
    
    func notifyReachabilityChanged() {
        let notification = { [weak self] in
            guard let `self` = self else { return }
            NotificationCenter.default.post(name: .reachabilityChanged, object: self.apiConnection)
        }
        notificationQueue.async(execute: notification)
    }
    
    class func resolvedIpAddress(fromDomainName domainName: String) -> String? {
        
        let host = CFHostCreateWithName(nil,domainName as CFString).takeRetainedValue()
        
        CFHostStartInfoResolution(host, .addresses, nil)
        var success: DarwinBoolean = false
        
        if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray?,
            let theAddress = addresses.firstObject as? NSData
        {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(theAddress.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(theAddress.length),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}

extension Reachability {
    
    enum Connection: CustomStringConvertible {
        case none, unavailable, wifi, cellular
        public var description: String {
            switch self {
            case .cellular: return "Cellular"
            case .wifi: return "WiFi"
            case .unavailable: return "No Connection"
            case .none: return "unavailable"
            }
        }
        public var available: Bool {
            self == .cellular || self == .wifi
        }
    }
    
    func startNotifier() throws {
        guard !notifierRunning else { return }
        
        let callback: SCNetworkReachabilityCallBack = { (reachability, flags, info) in
            guard let info = info else { return }
            
            // `weakifiedReachability` is guaranteed to exist by virtue of our
            // retain/release callbacks which we provided to the `SCNetworkReachabilityContext`.
            let weakifiedReachability = Unmanaged<ReachabilityWeakifier>.fromOpaque(info).takeUnretainedValue()
            
            // The weak `reachability` _may_ no longer exist if the `Reachability`
            // object has since been deallocated but a callback was already in flight.
            weakifiedReachability.reachability?.flags = flags
        }
        
        let weakifiedReachability = ReachabilityWeakifier(reachability: self)
        let opaqueWeakifiedReachability = Unmanaged<ReachabilityWeakifier>.passUnretained(weakifiedReachability).toOpaque()
        
        var context = SCNetworkReachabilityContext(
            version: 0,
            info: UnsafeMutableRawPointer(opaqueWeakifiedReachability),
            retain: { (info: UnsafeRawPointer) -> UnsafeRawPointer in
                let unmanagedWeakifiedReachability = Unmanaged<ReachabilityWeakifier>.fromOpaque(info)
                _ = unmanagedWeakifiedReachability.retain()
                return UnsafeRawPointer(unmanagedWeakifiedReachability.toOpaque())
        },
            release: { (info: UnsafeRawPointer) -> Void in
                let unmanagedWeakifiedReachability = Unmanaged<ReachabilityWeakifier>.fromOpaque(info)
                unmanagedWeakifiedReachability.release()
        },
            copyDescription: { (info: UnsafeRawPointer) -> Unmanaged<CFString> in
                let unmanagedWeakifiedReachability = Unmanaged<ReachabilityWeakifier>.fromOpaque(info)
                let weakifiedReachability = unmanagedWeakifiedReachability.takeUnretainedValue()
                let description = weakifiedReachability.reachability?.description ?? "nil"
                return Unmanaged.passRetained(description as CFString)
        }
        )
        
        if !SCNetworkReachabilitySetCallback(reachabilityRef, callback, &context) {
            stopNotifier()
            throw ReachabilityError.unableToSetCallback(SCError())
        }
        
        if !SCNetworkReachabilitySetDispatchQueue(reachabilityRef, reachabilitySerialQueue) {
            stopNotifier()
            throw ReachabilityError.unableToSetDispatchQueue(SCError())
        }
        
        try setReachabilityFlags()
        
        notifierRunning = true
    }
    
    func stopNotifier() {
        defer { notifierRunning = false }
        
        SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachabilityRef, nil)
    }
    
    var description: String {
        return flags?.description ?? "unavailable flags"
    }
}


extension SCNetworkReachabilityFlags {
    
    typealias Connection = Reachability.Connection
    
    var connection: Connection {
        guard isReachableFlagSet else { return .unavailable }
        
        // If we're reachable, but not on an iOS device (i.e. simulator), we must be on WiFi
        #if targetEnvironment(simulator)
        return .wifi
        #else
        var connection = Connection.unavailable
        
        if !isConnectionRequiredFlagSet {
            connection = .wifi
        }
        
        if isConnectionOnTrafficOrDemandFlagSet && !isInterventionRequiredFlagSet {
            connection = .wifi
        }
        
        if isOnWWANFlagSet {
            connection = .cellular
        }
        
        return connection
        #endif
    }
    
    var isOnWWANFlagSet: Bool {
        #if os(iOS)
        return contains(.isWWAN)
        #else
        return false
        #endif
    }
    var isReachableFlagSet: Bool {
        return contains(.reachable)
    }
    var isConnectionRequiredFlagSet: Bool {
        return contains(.connectionRequired)
    }
    var isInterventionRequiredFlagSet: Bool {
        return contains(.interventionRequired)
    }
    var isConnectionOnTrafficFlagSet: Bool {
        return contains(.connectionOnTraffic)
    }
    var isConnectionOnDemandFlagSet: Bool {
        return contains(.connectionOnDemand)
    }
    var isConnectionOnTrafficOrDemandFlagSet: Bool {
        return !intersection([.connectionOnTraffic, .connectionOnDemand]).isEmpty
    }
    var isTransientConnectionFlagSet: Bool {
        return contains(.transientConnection)
    }
    var isLocalAddressFlagSet: Bool {
        return contains(.isLocalAddress)
    }
    var isDirectFlagSet: Bool {
        return contains(.isDirect)
    }
    var isConnectionRequiredAndTransientFlagSet: Bool {
        return intersection([.connectionRequired, .transientConnection]) == [.connectionRequired, .transientConnection]
    }
    
    var description: String {
        let W = isOnWWANFlagSet ? "W" : "-"
        let R = isReachableFlagSet ? "R" : "-"
        let c = isConnectionRequiredFlagSet ? "c" : "-"
        let t = isTransientConnectionFlagSet ? "t" : "-"
        let i = isInterventionRequiredFlagSet ? "i" : "-"
        let C = isConnectionOnTrafficFlagSet ? "C" : "-"
        let D = isConnectionOnDemandFlagSet ? "D" : "-"
        let l = isLocalAddressFlagSet ? "l" : "-"
        let d = isDirectFlagSet ? "d" : "-"
        
        return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)"
    }
}

/**
 `ReachabilityWeakifier` weakly wraps the `Reachability` class
 in order to break retain cycles when interacting with CoreFoundation.
 CoreFoundation callbacks expect a pair of retain/release whenever an
 opaque `info` parameter is provided. These callbacks exist to guard
 against memory management race conditions when invoking the callbacks.
 #### Race Condition
 If we passed `SCNetworkReachabilitySetCallback` a direct reference to our
 `Reachability` class without also providing corresponding retain/release
 callbacks, then a race condition can lead to crashes when:
 - `Reachability` is deallocated on thread X
 - A `SCNetworkReachability` callback(s) is already in flight on thread Y
 #### Retain Cycle
 If we pass `Reachability` to CoreFoundtion while also providing retain/
 release callbacks, we would create a retain cycle once CoreFoundation
 retains our `Reachability` class. This fixes the crashes and his how
 CoreFoundation expects the API to be used, but doesn't play nicely with
 Swift/ARC. This cycle would only be broken after manually calling
 `stopNotifier()` — `deinit` would never be called.
 #### ReachabilityWeakifier
 By providing both retain/release callbacks and wrapping `Reachability` in
 a weak wrapper, we:
 - interact correctly with CoreFoundation, thereby avoiding a crash.
 See "Memory Management Programming Guide for Core Foundation".
 - don't alter the public API of `Reachability.swift` in any way
 - still allow for automatic stopping of the notifier on `deinit`.
 */
private class ReachabilityWeakifier {
    weak var reachability: Reachability?
    init(reachability: Reachability) {
        self.reachability = reachability
    }
}
