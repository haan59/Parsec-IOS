import Foundation
import Network

class NetworkHandler {
	public static var clinfo: ClientInfo?
}

class NetworkWatcher {
	static let shared = NetworkWatcher()

	private let monitor = NWPathMonitor()
	private let queue = DispatchQueue(label: "netwatch")
	private var running = false
	private var offline = false
	private(set) var noNetwork = false
	private var known = false
	private var interface: NWInterface.InterfaceType?
	private(set) var interfaceChanges = 0
	private var waiting: [() -> Void] = []

	var onReturn: (() -> Void)?

	func start() {
		if running { return }
		running = true

		monitor.pathUpdateHandler = { [weak self] path in
			let status = path.status
			let type = [NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet].first { path.usesInterfaceType($0) }
			DispatchQueue.main.async {
				guard let self = self else { return }
				self.noNetwork = status == .unsatisfied
				if status == .satisfied, let type = type {
					if let old = self.interface, old != type {
						self.interfaceChanges += 1
					}
					self.interface = type
				}
				if !self.known {
					self.known = true
					let runs = self.waiting
					self.waiting = []
					runs.forEach { $0() }
				}
				if status == .satisfied {
					guard self.offline else { return }
					self.offline = false
					self.onReturn?()
				} else {
					self.offline = true
				}
			}
		}

		monitor.start(queue: queue)
	}

	func whenKnown(_ run: @escaping () -> Void) {
		if known { run() } else { waiting.append(run) }
	}
}

struct ErrorInfo: Decodable {
	var error: String
//	var codes:Array
}

struct ClientInfo: Decodable {
	var instance_id: String
	var user_id: Int
	var session_id: String
	var host_peer_id: String
}

struct UserInfo: Decodable {
	var id: Int
	var name: String
	var warp: Bool
//	var external_id: String
//	var external_provider: String
	var team_id: String
}

struct HostInfo: Decodable {
	var user: UserInfo
	var peer_id: String
	var game_id: String
	var description: String
	var max_players: Int
	var mode: String
	var name: String
	var event_name: String
	var players: Int
//	var public: Bool
	var guest_access: Bool
	var online: Bool
//	var self: Bool
	var build: String
}

struct HostInfoList: Decodable {
	var data: [HostInfo]?
	var has_more: Bool
}

struct SelfInfoData: Decodable {
	var id: Int
	var name: String
	var email: String
	var warp: Bool
	var staff: Bool
	var team_id: String
	var is_confirmed: Bool
	var team_is_active: Bool
	var is_saml: Bool
	var is_gateway_enabled: Bool
	var is_relay_enabled: Bool
	var has_tfa: Bool
//	var app_config:Any
	var cohort_channel: String
}

struct SelfInfo: Decodable {
	var data: SelfInfoData
}

struct FriendInfo: Decodable {
	var user_id: Int
	var user_name: String
}

struct FriendInfoList: Decodable {
	var data: [FriendInfo]?
	var has_more: Bool
}

struct FriendRequestUser: Decodable {
	var id: Int
	var name: String
}

struct FriendRequestInfo: Decodable {
	var user: FriendRequestUser
}

struct FriendRequestList: Decodable {
	var data: [FriendRequestInfo]?
	var has_more: Bool
}

struct UserSearchResult: Decodable, Identifiable {
	var id: Int
	var name: String
	var is_friend: Bool?
	var is_friend_requested: Bool?
}

struct UserSearchList: Decodable {
	var data: [UserSearchResult]?
}

enum KesselResult<T> {
	case ok(T)
	case unauthorized
	case failed(String)
}

// Calls to kessel-api.parsec.app. Results come back on the main thread.
enum Kessel {
	static let base = "https://kessel-api.parsec.app"
	static let userAgent = "parsec/150-93b Windows/11 libmatoya/4.0"

	static func send(_ method: String, _ path: String, body: [String: Any]? = nil, done: @escaping (KesselResult<Data>) -> Void) {
		guard let session = NetworkHandler.clinfo?.session_id else {
			done(.unauthorized)
			return
		}
		guard let url = URL(string: base + path) else {
			done(.failed("Bad request"))
			return
		}

		var request = URLRequest(url: url)
		request.httpMethod = method
		request.timeoutInterval = 15
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		if let body = body {
			request.httpBody = try? JSONSerialization.data(withJSONObject: body)
		}

		URLSession.shared.dataTask(with: request) { data, response, _ in
			let result: KesselResult<Data>
			if let status = (response as? HTTPURLResponse)?.statusCode {
				if status == 401 {
					result = .unauthorized
				} else if (200..<300).contains(status) {
					result = .ok(data ?? Data())
				} else if let data = data, let info = try? JSONDecoder().decode(ErrorInfo.self, from: data), !info.error.isEmpty {
					result = .failed(info.error.prefix(1).uppercased() + info.error.dropFirst())
				} else {
					result = .failed("Parsec returned HTTP \(status)")
				}
			} else {
				result = .failed("Can't reach Parsec")
			}
			DispatchQueue.main.async { done(result) }
		}.resume()
	}

	static func get<T: Decodable>(_ path: String, as type: T.Type, done: @escaping (KesselResult<T>) -> Void) {
		send("GET", path) { result in
			switch result {
			case .ok(let data):
				if let value = try? JSONDecoder().decode(T.self, from: data) {
					done(.ok(value))
				} else {
					done(.failed("Bad response from Parsec"))
				}
			case .unauthorized:
				done(.unauthorized)
			case .failed(let message):
				done(.failed(message))
			}
		}
	}
}

// How the share link secret is handed to the SDK. Still being tested, so the user can pick.
enum SecretMethod: String, CaseIterable {
	case config = "Config"         // ParsecClientConfig.secret
	case peerString = "Peer string" // "peer_id=X:host_secret=Y" as the peer id, like Parsec for Windows
	case none = "None"             // peer id only, secret not sent

	static var saved: SecretMethod {
		get { SecretMethod(rawValue: UserDefaults.standard.string(forKey: "shareSecretMethod") ?? "") ?? .config }
		set { UserDefaults.standard.set(newValue.rawValue, forKey: "shareSecretMethod") }
	}
}

// Share links you joined before, newest first, so you can reconnect without asking for a new link.
struct RecentLink: Codable, Identifiable {
	var peer: String
	var secret: String?
	var hostName: String
	var userName: String
	var userId: Int
	var usedAt: Date

	var id: String { peer }

	private static let key = "recentShareLinks"
	private static let limit = 8

	static func load() -> [RecentLink] {
		guard let data = UserDefaults.standard.data(forKey: key),
			  let list = try? JSONDecoder().decode([RecentLink].self, from: data) else { return [] }
		return list
	}

	static func save(_ list: [RecentLink]) {
		if let data = try? JSONEncoder().encode(Array(list.prefix(limit))) {
			UserDefaults.standard.set(data, forKey: key)
		}
	}

	static func remember(_ link: RecentLink) {
		var list = load().filter { $0.peer != link.peer }
		list.insert(link, at: 0)
		save(list)
	}

	static func forget(_ peer: String) {
		save(load().filter { $0.peer != peer })
	}
}

struct ShareSecret {
	var peer: String
	var secret: String
	var method: SecretMethod
}

struct PublicHostUser: Decodable {
	var id: Int
	var name: String
}

struct PublicHost: Decodable {
	var name: String
	var user: PublicHostUser
	var players: Int?
	var max_players: Int?
}

private struct PublicHostEnvelope: Decodable {
	var data: PublicHost
}

enum ShareLink {
	// Accepts parsec.gg/g/<peer>/<secret>/, dash.parsec.app/join-computer?peer=&secret=,
	// parsec://peer_id=X&host_secret=Y, or a bare peer id.
	static func parse(_ text: String) -> (peer: String, secret: String?)? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		if let range = trimmed.range(of: "/g/") {
			let parts = trimmed[range.upperBound...].split(separator: "/").map(String.init)
			if parts.count >= 2, isToken(parts[0]), isToken(parts[1]) {
				return (parts[0], parts[1])
			}
			if parts.count == 1, isToken(parts[0]) {
				return (parts[0], nil)
			}
			return nil
		}

		let query = queryItems(trimmed)
		if let peer = query["peer"] ?? query["peer_id"], isToken(peer) {
			let secret = query["secret"] ?? query["host_secret"]
			return (peer, secret.flatMap { isToken($0) ? $0 : nil })
		}

		if isToken(trimmed), trimmed.count >= 16 {
			return (trimmed, nil)
		}
		return nil
	}

	private static func queryItems(_ text: String) -> [String: String] {
		var items: [String: String] = [:]
		var rest = text
		if let q = rest.firstIndex(of: "?") {
			rest = String(rest[rest.index(after: q)...])
		} else if let scheme = rest.range(of: "://") {
			rest = String(rest[scheme.upperBound...])
		}
		for pair in rest.split(whereSeparator: { $0 == "&" || $0 == ":" }) {
			let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
			if kv.count == 2 {
				items[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
			}
		}
		return items
	}

	private static func isToken(_ s: String) -> Bool {
		!s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" }
	}

	// Same lookup the Parsec join page does. 404 means the host is offline or the link is no longer valid.
	static func lookup(peer: String, secret: String?, done: @escaping (KesselResult<PublicHost>) -> Void) {
		var path = "/public/hosts/\(peer)"
		if let secret = secret { path += "?secret=\(secret)" }
		guard let url = URL(string: Kessel.base + path) else {
			done(.failed("Bad link"))
			return
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 15
		request.setValue(Kessel.userAgent, forHTTPHeaderField: "User-Agent")
		if let session = NetworkHandler.clinfo?.session_id {
			request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
		}
		URLSession.shared.dataTask(with: request) { data, response, _ in
			let result: KesselResult<PublicHost>
			let status = (response as? HTTPURLResponse)?.statusCode
			if status == 200, let data = data,
			   let host = (try? JSONDecoder().decode(PublicHostEnvelope.self, from: data))?.data ?? (try? JSONDecoder().decode(PublicHost.self, from: data)) {
				result = .ok(host)
			} else if status == 404 {
				result = .failed("Host not found. It may be offline, or the link may have expired.")
			} else if let status = status {
				result = .failed("Parsec returned HTTP \(status)")
			} else {
				result = .failed("Can't reach Parsec")
			}
			DispatchQueue.main.async { done(result) }
		}.resume()
	}
}

// Friend endpoints. Every write takes the other person's user id.
enum FriendsAPI {
	static func requests(incoming: Bool, done: @escaping (KesselResult<[IdentifiableUserInfo]>) -> Void) {
		Kessel.get("/friend-requests?direction=\(incoming ? "incoming" : "outgoing")", as: FriendRequestList.self) { result in
			switch result {
			case .ok(let list):
				done(.ok((list.data ?? []).map { IdentifiableUserInfo(id: $0.user.id, username: $0.user.name) }))
			case .unauthorized:
				done(.unauthorized)
			case .failed(let message):
				done(.failed(message))
			}
		}
	}

	static func sendRequest(_ userId: Int, done: @escaping (KesselResult<Data>) -> Void) {
		Kessel.send("POST", "/friend-requests", body: ["user_id": userId], done: done)
	}

	static func accept(_ userId: Int, done: @escaping (KesselResult<Data>) -> Void) {
		Kessel.send("PUT", "/friend-requests", body: ["user_id": userId], done: done)
	}

	// Declines a request they sent, or cancels one you sent.
	static func removeRequest(_ userId: Int, done: @escaping (KesselResult<Data>) -> Void) {
		Kessel.send("DELETE", "/friend-requests", body: ["user_id": userId], done: done)
	}

	static func unfriend(_ userId: Int, done: @escaping (KesselResult<Data>) -> Void) {
		Kessel.send("DELETE", "/friendships", body: ["user_id": userId], done: done)
	}

	// Parsec only searches by name, not by the number.
	static func search(_ name: String, done: @escaping (KesselResult<[UserSearchResult]>) -> Void) {
		let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
		let escaped = name.addingPercentEncoding(withAllowedCharacters: unreserved) ?? name
		Kessel.get("/users?search=\(escaped)", as: UserSearchList.self) { result in
			switch result {
			case .ok(let list):
				done(.ok(list.data ?? []))
			case .unauthorized:
				done(.unauthorized)
			case .failed(let message):
				done(.failed(message))
			}
		}
	}

	// "Name#123", "Name #123", "Name\n#123" or "123" -> name and id. Anything else is a name.
	static func parseUserTag(_ text: String) -> (name: String, id: Int?) {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if let hash = trimmed.lastIndex(of: "#") {
			let name = trimmed[..<hash].trimmingCharacters(in: .whitespacesAndNewlines)
			let number = trimmed[trimmed.index(after: hash)...].trimmingCharacters(in: .whitespacesAndNewlines)
			if let id = Int(number), id > 0 {
				return (name, id)
			}
		}
		if let id = Int(trimmed), id > 0 {
			return ("", id)
		}
		return (trimmed, nil)
	}
}
