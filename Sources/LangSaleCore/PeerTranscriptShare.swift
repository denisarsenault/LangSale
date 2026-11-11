import Foundation
import MultipeerConnectivity

/// Shares finished transcript text between devices the user has paired.
///
/// Only `Transcript` text is sent. Audio never leaves the device. Sessions require encryption.
/// Incoming invitations go through `approve`, which the app should back with a visible user prompt.
public final class PeerTranscriptShare: NSObject, @unchecked Sendable {
    /// Bonjour service type: 1–15 lowercase ASCII characters, hyphens allowed.
    public static let serviceType = "langsale-tx"
    private static let maxMessageBytes = 64 * 1024

    public enum Event: Sendable {
        case transcript(Transcript)
        case peerConnected(String)
        case peerDisconnected(String)
    }

    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let approve: @Sendable (String) -> Bool

    /// - Parameters:
    ///   - displayName: Name shown to peers. Use a device label the user chose, not a personal name.
    ///   - approve: Called with the inviting peer's name. Return true only after user confirmation.
    public init(displayName: String, approve: @escaping @Sendable (String) -> Bool) {
        peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil,
                                               serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        self.approve = approve

        let stream = AsyncStream.makeStream(of: Event.self)
        events = stream.stream
        continuation = stream.continuation

        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    deinit {
        continuation.finish()
    }

    public func startDiscovery() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func stopDiscovery() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }

    public func share(_ transcript: Transcript) throws {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        let data = try JSONEncoder().encode(transcript)
        guard data.count <= Self.maxMessageBytes else { return }
        try session.send(data, toPeers: peers, with: .reliable)
    }
}

extension PeerTranscriptShare: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: continuation.yield(.peerConnected(peerID.displayName))
        case .notConnected: continuation.yield(.peerDisconnected(peerID.displayName))
        default: break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= Self.maxMessageBytes,
              let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else { return }
        continuation.yield(.transcript(transcript))
    }

    public func session(_ session: MCSession, didReceive stream: InputStream,
                        withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, with progress: Progress) {}

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerTranscriptShare: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                           didReceiveInvitationFromPeer peerID: MCPeerID,
                           withContext context: Data?,
                           invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let accept = approve(peerID.displayName)
        invitationHandler(accept, accept ? session : nil)
    }
}

extension PeerTranscriptShare: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                        withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
