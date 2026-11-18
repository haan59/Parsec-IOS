import SwiftUI
import ParsecSDK

struct MainView: View {
	var controller: ContentView?

	@State private var page: Page = .hosts

	// Host page vars
	@State var hostCountStr: String = "0 hosts"
	@State var refreshTime: String = ""

	@State var hosts: [IdentifiableHostInfo] = []

	// Friend page vars
	@State var friendCountStr: String = "0 friends"

	@State var userInfo: IdentifiableUserInfo?
	@State var friends: [IdentifiableUserInfo] = []
	@State var friendsLoaded = false
	@State var incomingRequests: [IdentifiableUserInfo] = []
	@State var outgoingRequests: [IdentifiableUserInfo] = []
	@State var friendBusy: Set<Int> = []
	@State var friendsError: String?
	@State var showAddFriend = false
	@State var unfriendTarget: IdentifiableUserInfo?
	@State var showUnfriendAlert = false

	@State var showJoinLink = false

	// Global vars
	@State var showBaseAlert: Bool = false
	@State var baseAlertText: String = ""

	@State var showLogoutAlert: Bool = false

	@State var isConnecting: Bool = false
	@State var waitingForApproval: Bool = false
	@State var retryingConnect: Bool = false
	@State var connectPolls = 0
	@State var connectingToName: String = ""
	@State var pollTimer: Timer?
	@State var approvalStartedAt: Date?
	@State var connectStartedAt = Date()

	@State var isRefreshing: Bool = false
	@State var refreshError: String?

	@State var inSettings: Bool = false
	@State var sessionExpired: Bool = false

	@State private var lastHostShown: String?

	var busy: Bool {
		isConnecting || inSettings
	}

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var body: some View {
		ZStack {
			// Background
			Rectangle()
				.fill(Color("BackgroundTab"))
				.edgesIgnoringSafeArea(.all)
			Rectangle()
				.fill(Color("BackgroundGray"))
				.padding(.vertical, 52)

			// Main controls
			VStack {
				// Navigation controls
				HStack {
					Button(action: { showLogoutAlert = true }, label: { Image("SymbolExit").scaleEffect(x: -1) })
						.padding()
						.alert(isPresented: $showLogoutAlert) {
							Alert(title: Text("Are you sure you want to logout?"), primaryButton: .destructive(Text("Logout"), action: logout), secondaryButton: .cancel(Text("Cancel")))
						}
//					Button(action: {
//						if let c = controller
//						{
//							c.setView(.test)
//
//						}
//						
//					}, label: {
//						Text("Show TestView")
//					})

					Spacer()
					HStack {
						if page == .hosts {
							Button(action: { showJoinLink = true }, label: { Image(systemName: "link") })
								.padding(4)
								.accessibility(label: Text("Join with a share link"))
								.sheet(isPresented: $showJoinLink) {
									JoinLinkView(onConnect: { host, share in
										showJoinLink = false
										// let the sheet finish closing before the connecting overlay shows
										DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
											connectTo(host, share: share)
										}
									})
								}

							Text(hostCountStr)
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
							Button(action: refreshHosts, label: { Image(systemName: "arrow.clockwise") })
								.padding(4)
								.disabled(isRefreshing)
								.opacity(isRefreshing ? 0.4 : 1)
						} else if page == .friends {
							Image(systemName: "person.badge.plus")
								.padding(4)
								.opacity(0)

							Text(friendCountStr)
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
							Button(action: { showAddFriend = true }, label: { Image(systemName: "person.badge.plus") })
								.padding(4)
								.accessibility(label: Text("Add Friend"))
						}
					}
					Spacer()
					Button(action: { withAnimation(.easeInOut(duration: 0.24)) { inSettings = true } }, label: { Image(systemName: "gear") })
						.padding()
				}
				.foregroundColor(Color("AccentColor"))
				.background(Color("BackgroundTab")
					.frame(height: 52)
					.shadow(color: Color("Shading"), radius: 4, y: 6)
					.mask(Rectangle().frame(height: 80).offset(y: 50))
				)
				.zIndex(1)

				ZStack {
					// Hosts page
					ScrollView(.vertical) {
						VStack {
							if sessionExpired {
								HStack {
									Text("Your Parsec session expired")
										.foregroundColor(Color("Foreground"))
									Spacer()
									Button(action: logout) {
										Text("Sign In")
											.fontWeight(.semibold)
											.foregroundColor(Color("AccentColor"))
											.frame(minWidth: 44, minHeight: 44)
											.contentShape(Rectangle())
									}
								}
								.padding(.horizontal, 12)
								.padding(.vertical, 2)
								.background(Rectangle().fill(Color("BackgroundPrompt")))
								.cornerRadius(8)
								.frame(maxWidth: 400)
								.padding(.horizontal)
							}
							if let refreshError = refreshError {
								HStack {
									Text(refreshError)
										.foregroundColor(Color("Foreground"))
									Spacer()
									Button(action: refreshHosts) {
										Text("Retry")
											.fontWeight(.semibold)
											.foregroundColor(Color("AccentColor"))
											.frame(minWidth: 44, minHeight: 44)
											.contentShape(Rectangle())
									}
								}
								.padding(.horizontal, 12)
								.padding(.vertical, 2)
								.background(Rectangle().fill(Color("BackgroundPrompt")))
								.cornerRadius(8)
								.frame(maxWidth: 400)
								.padding(.horizontal)
							}
							if isRefreshing {
								HStack(spacing: 8) {
									ActivityIndicator(isAnimating: $isRefreshing, style: .medium, tint: UIColor(named: "Foreground") ?? .white)
										.frame(width: 20, height: 20)
									Text("Refreshing hosts...")
										.foregroundColor(Color("Foreground"))
								}
							} else if !refreshTime.isEmpty {
								Text(refreshTime)
									.multilineTextAlignment(.center)
									.opacity(0.5)
							}
							if let lastHost = lastHostShown, !isConnecting {
								VStack(spacing: 0) {
									HStack {
										VStack(alignment: .leading, spacing: 4) {
											Text("Last connected")
												.font(.system(size: 12))
												.opacity(0.5)
											Text(lastHost)
												.font(.system(size: 16, weight: .medium))
										}
										Spacer()
										Button(action: reconnectLastHost) {
											Text("Reconnect")
												.lineLimit(1)
												.fixedSize()
												.foregroundColor(.white)
												.padding(.horizontal, 16)
												.frame(minHeight: 44)
												.background(Color("AccentColor"))
												.cornerRadius(8)
										}
										Button(action: clearLastHost) {
											Image(systemName: "xmark")
												.foregroundColor(Color("Foreground"))
												.opacity(0.5)
												.frame(width: 44, height: 44)
												.contentShape(Rectangle())
										}
									}
									.padding()
									HStack {
										Toggle("Reconnect on app launch", isOn: Binding(
											get: { SettingsHandler.autoConnectOnLaunch },
											set: { SettingsHandler.autoConnectOnLaunch = $0 }
										))
										.font(.system(size: 13))
										.opacity(0.7)
									}
									.padding(.horizontal)
									.padding(.bottom, 10)
								}
								.frame(maxWidth: 400)
								.background(Rectangle().fill(Color("BackgroundCard")))
								.cornerRadius(8)
							}
							ForEach(hosts) { i in
								ZStack {
									VStack {
										URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=64,h=64,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(i.user.id))/avatar"),
												output:
												{
													$0
														.resizable()
														.aspectRatio(contentMode: .fit)
														.frame(width: 64, height: 64)
														.cornerRadius(8)
												},
												placeholder:
												{
													Image("IconTransparent")
														.resizable()
														.aspectRatio(contentMode: .fit)
														.frame(width: 64, height: 64)
														.background(Rectangle().fill(Color("BackgroundPrompt")))
														.cornerRadius(8)
												})
										Text(i.hostname)
											.font(.system(size: 20, weight: .medium))
											.multilineTextAlignment(.center)
										Text("\(i.user.name)#\(String(i.user.id))")
											.font(.system(size: 16, weight: .medium))
											.multilineTextAlignment(.center)
											.opacity(0.5)
										Button(action: { connectTo(i) }) {
											Text("Connect")
												.lineLimit(1)
												.fixedSize()
												.foregroundColor(.white)
												.padding(.horizontal, 28)
												.frame(minHeight: 44)
												.background(Color("AccentColor"))
												.cornerRadius(8)
										}
									}

									if i.connections > 0 {
										VStack {
											HStack {
												Image(systemName: "person.fill")
												Text(String(i.connections))
													.font(.system(size: 16, weight: .medium))
												Spacer()
											}
											Spacer()
										}
									}
								}
								.padding()
								.frame(maxWidth: 400)
								.background(Rectangle().fill(Color("BackgroundCard")))
								.cornerRadius(8)
								.contextMenu {
									Button(action: { UIPasteboard.general.string = i.hostname }) {
										Label("Copy Name", systemImage: "doc.on.doc")
									}
								}
							}
						}
						.padding()
					}
					.zIndex(page == .hosts ? 0 : -1)
					.disabled(page != .hosts)
					.opacity(page == .hosts ? 1 : 0)

					// Friends page
					ScrollView(.vertical) {
						VStack {
							if sessionExpired {
								promptBanner("Your Parsec session expired", button: "Sign In", action: logout)
							}
							if let friendsError = friendsError {
								promptBanner(friendsError, button: "Retry", action: refreshFriends)
							}
							if let user = userInfo {
								Text("You")
									.multilineTextAlignment(.center)
									.opacity(0.5)
								friendRow(user) { EmptyView() }
							}
							if !incomingRequests.isEmpty {
								Text("Friend Requests")
									.multilineTextAlignment(.center)
									.opacity(0.5)
									.padding(.top, 8)
								ForEach(incomingRequests) { i in
									friendRow(i) {
										Button(action: { acceptRequest(i) }) {
											Text("Accept")
												.lineLimit(1)
												.fixedSize()
												.foregroundColor(.white)
												.padding(.horizontal, 16)
												.frame(minHeight: 44)
												.background(Color("AccentColor"))
												.cornerRadius(8)
										}
										Button(action: { declineRequest(i) }) {
											Image(systemName: "xmark")
												.foregroundColor(Color("Foreground"))
												.opacity(0.5)
												.frame(width: 44, height: 44)
												.contentShape(Rectangle())
										}
										.accessibility(label: Text("Decline \(i.username)"))
									}
								}
							}
							if !outgoingRequests.isEmpty {
								Text("Sent Requests")
									.multilineTextAlignment(.center)
									.opacity(0.5)
									.padding(.top, 8)
								ForEach(outgoingRequests) { i in
									friendRow(i) {
										Button(action: { cancelRequest(i) }) {
											Text("Cancel")
												.lineLimit(1)
												.fixedSize()
												.foregroundColor(Color("AccentColor"))
												.padding(.horizontal, 12)
												.frame(minHeight: 44)
												.contentShape(Rectangle())
										}
									}
								}
							}
							if friends.count > 0 {
								Text("Friends")
									.multilineTextAlignment(.center)
									.opacity(0.5)
									.padding(.top, 8)
								ForEach(friends) { i in
									friendRow(i) { EmptyView() }
										.contextMenu {
											Button(action: { UIPasteboard.general.string = "\(i.username)#\(String(i.id))" }) {
												Label("Copy Name#ID", systemImage: "doc.on.doc")
											}
											Button(action: {
												unfriendTarget = i
												showUnfriendAlert = true
											}) {
												Label("Unfriend", systemImage: "person.badge.minus")
											}
										}
								}
							} else if friendsLoaded && incomingRequests.isEmpty && outgoingRequests.isEmpty {
								VStack(spacing: 8) {
									Text("No friends yet")
										.font(.system(size: 17, weight: .semibold))
									Text("Add someone with their Parsec Name#ID, or search for their name.")
										.font(.system(size: 14))
										.multilineTextAlignment(.center)
										.opacity(0.6)
									Button(action: { showAddFriend = true }) {
										Text("Add Friend")
											.lineLimit(1)
											.fixedSize()
											.foregroundColor(.white)
											.padding(.horizontal, 28)
											.frame(minHeight: 44)
											.background(Color("AccentColor"))
											.cornerRadius(8)
									}
									.padding(.top, 4)
								}
								.padding(.top, 24)
								.padding(.horizontal)
							}
						}
						.padding()
					}
					.alert(isPresented: $showUnfriendAlert) {
						let name = unfriendTarget.map { "\($0.username)#\(String($0.id))" } ?? "this friend"
						return Alert(title: Text("Unfriend \(name)?"),
									 message: Text("They won't see or have access to your computers anymore."),
									 primaryButton: .destructive(Text("Unfriend")) { if let t = unfriendTarget { unfriend(t) } },
									 secondaryButton: .cancel(Text("Keep Friend")))
					}
					.zIndex(page == .friends ? 0 : -1)
					.disabled(page != .friends)
					.opacity(page == .friends ? 1 : 0)
				}
				.padding(.top, -8)
				.frame(maxWidth: .infinity)
				.alert(isPresented: $showBaseAlert) {
					Alert(title: Text(baseAlertText))
				}

				// Page controls
				HStack {
					Spacer()
					Button(action: { page = .hosts }, label:
					{
						VStack {
							Image(systemName: "desktopcomputer")
							Text("Hosts")
						}
					})
					.foregroundColor(Color(page == .hosts ? "AccentColor" : "ForegroundInactive"))
					.disabled(page == .hosts)
					Spacer()
					Button(action: {
						page = .friends
						refreshFriends()
					}, label:
					{
						VStack {
							Image(systemName: "person.2.fill")
								.overlay(Group {
									if !incomingRequests.isEmpty {
										Text(String(incomingRequests.count))
											.font(.system(size: 11, weight: .bold))
											.foregroundColor(.white)
											.padding(.horizontal, 5)
											.frame(minWidth: 17, minHeight: 17)
											.background(Capsule().fill(Color.red))
											.offset(x: 12, y: -8)
									}
								}, alignment: .topTrailing)
							Text("Friends")
						}
					})
					.accessibility(label: Text(incomingRequests.isEmpty ? "Friends" : "Friends, \(incomingRequests.count) pending requests"))
					.foregroundColor(Color(page == .friends ? "AccentColor" : "ForegroundInactive"))
					.disabled(page == .friends)
					Spacer()
				}
				.padding([.leading, .bottom, .trailing], 4)
				.background(Color("BackgroundTab")
					.padding(.top, -8)
					.shadow(color: Color("Shading"), radius: 4, y: -2)
					.mask(Rectangle().frame(height: 80).offset(y: -50))
				)
				.zIndex(1)
			}
			.onAppear(perform: initView)
			.onDisappear { ParsecBackgroundManager.shared.onShortcutReconnect = nil }
			.sheet(isPresented: $showAddFriend) {
				AddFriendView(onChange: refreshRequests, onUnauthorized: { sessionExpired = true })
			}
			.disabled(busy) // disable view if busy

			// Settings screen
			SettingsView(visible: $inSettings)

			// Loading elements
			if isConnecting {
				VStack(spacing: 12) {
					ActivityIndicator(isAnimating: $isConnecting, style: .large, tint: .white)
					Text(waitingForApproval ? "Waiting for \(connectingToName) to approve you..." : retryingConnect ? "\(connectingToName) didn't answer, trying again..." : "Requesting connection to \(connectingToName)...")
						.font(.system(size: 16, weight: .medium))
						.foregroundColor(.white)
						.multilineTextAlignment(.center)
						.padding(.horizontal)
					Button(action: cancelConnection) {
						Text("Cancel")
							.font(.system(size: 15, weight: .semibold))
							.foregroundColor(.white)
							.padding(.horizontal, 20)
							.frame(minHeight: 44)
							.background(Color.white.opacity(0.2))
							.cornerRadius(8)
					}
					.padding(.top, 4)
					if SettingsHandler.showConnectionLog {
						ConnectionLogPanel()
					}
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(Color.black.opacity(0.85).edgesIgnoringSafeArea(.all))
			}
		}
		.foregroundColor(Color("Foreground"))
	}

	func initView() {
		lastHostShown = ParsecBackgroundManager.shared.lastPeerId != nil ? ParsecBackgroundManager.shared.lastHostname : nil
		refreshHosts()
		refreshSelf()
		refreshFriends()

		ParsecBackgroundManager.shared.onShouldReconnect = { peerId in
			if let host = hosts.first(where: { $0.id == peerId }) {
				connectTo(host)
			} else {
				refreshHosts()
			}
		}

		NetworkWatcher.shared.onReturn = {
			guard NetworkHandler.clinfo != nil, !ParsecBackgroundManager.shared.hasActiveConnection else { return }
			refreshHosts()
			refreshFriends()
		}
		NetworkWatcher.shared.start()

		ParsecBackgroundManager.shared.onShortcutReconnect = {
			if !isConnecting { reconnectLastHost() }
		}
		let pending = ParsecBackgroundManager.shared.reconnectPending
		ParsecBackgroundManager.shared.reconnectPending = false

		NetworkWatcher.shared.whenKnown {
			if (SettingsHandler.autoConnectOnLaunch && ParsecBackgroundManager.shared.resumeOnLaunch || pending) && !isConnecting && !ParsecBackgroundManager.shared.hasActiveConnection, ParsecBackgroundManager.shared.lastPeerId != nil {
				reconnectLastHost()
			}
		}
	}

	func reconnectLastHost() {
		guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
		let hostname = ParsecBackgroundManager.shared.lastHostname ?? peerId
		let user = UserInfo(id: 0, name: "", warp: false, team_id: "")
		let stub = IdentifiableHostInfo(id: peerId, hostname: hostname, user: user, connections: 0)
		appNote("[connect] last host from the saved id, host list \(hosts.isEmpty ? "not loaded yet" : "loaded")")
		connectTo(stub)
	}

	func clearLastHost() {
		ParsecBackgroundManager.shared.disableAutoReconnect()
		lastHostShown = nil
	}

	func refreshHosts() {
		guard !isRefreshing else { return }
		withAnimation {
			isRefreshing = true

			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				isRefreshing = false
				sessionExpired = true
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/v2/hosts?mode=desktop&public=false")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					defer { isRefreshing = false }

					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							refreshError = nil
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							sessionExpired = false
							guard let info: HostInfoList = try? decoder.decode(HostInfoList.self, from: data) else {
								refreshError = "Couldn't refresh hosts: bad response"
								return
							}
							refreshError = nil
							hosts.removeAll()
							if let datas = info.data {
								datas.forEach { h in
									hosts.append(IdentifiableHostInfo(id: h.peer_id, hostname: h.name, user: h.user, connections: h.players))
								}
							}
							if let lastId = ParsecBackgroundManager.shared.lastPeerId, let current = hosts.first(where: { $0.id == lastId }), current.hostname != ParsecBackgroundManager.shared.lastHostname {
								ParsecBackgroundManager.shared.lastHostname = current.hostname
								if lastHostShown != nil { lastHostShown = current.hostname }
							}

							var grammar: String = "hosts"
							if hosts.count == 1 {
								grammar = "host"
							}

							hostCountStr = "\(hosts.count) \(grammar)"

							let formatter = DateFormatter()
							formatter.dateStyle = .short
							formatter.timeStyle = .short
							refreshTime = "Last refreshed at \(formatter.string(from: Date()))"
						} else if statusCode == 403, let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) { // 403 Forbidden
							refreshError = "Couldn't refresh hosts: \(info.error)"
						} else {
							refreshError = "Couldn't refresh hosts (HTTP \(statusCode))"
						}
					} else {
						refreshError = "Can't reach Parsec"
					}
				}
			}
			task.resume()
		}
	}

	func refreshSelf() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/me")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let selfInfo = try? decoder.decode(SelfInfo.self, from: data) else { return }
							userInfo = IdentifiableUserInfo(id: selfInfo.data.id, username: selfInfo.data.name)
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = "Error gathering user info: \(info.error)"
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func refreshFriends() {
		guard NetworkHandler.clinfo != nil else { return }

		Kessel.get("/friendships", as: FriendInfoList.self) { result in
			switch result {
			case .ok(let info):
				friendsError = nil
				friends = (info.data ?? []).map { IdentifiableUserInfo(id: $0.user_id, username: $0.user_name) }
				friendCountStr = "\(friends.count) \(friends.count == 1 ? "friend" : "friends")"
				friendsLoaded = true
			case .unauthorized:
				sessionExpired = true
			case .failed(let message):
				friendsError = "Couldn't load friends: \(message)"
			}
		}
		refreshRequests()
	}

	func refreshRequests() {
		guard NetworkHandler.clinfo != nil else { return }

		FriendsAPI.requests(incoming: true) { result in
			if case .ok(let list) = result { incomingRequests = list }
			if case .unauthorized = result { sessionExpired = true }
		}
		FriendsAPI.requests(incoming: false) { result in
			if case .ok(let list) = result { outgoingRequests = list }
		}
	}

	func acceptRequest(_ user: IdentifiableUserInfo) {
		runFriendAction(user, failure: "Couldn't accept \(user.username)'s request", call: FriendsAPI.accept) {
			incomingRequests.removeAll { $0.id == user.id }
			if !friends.contains(where: { $0.id == user.id }) { friends.append(user) }
		}
	}

	func declineRequest(_ user: IdentifiableUserInfo) {
		runFriendAction(user, failure: "Couldn't decline \(user.username)'s request", call: FriendsAPI.removeRequest) {
			incomingRequests.removeAll { $0.id == user.id }
		}
	}

	func cancelRequest(_ user: IdentifiableUserInfo) {
		runFriendAction(user, failure: "Couldn't cancel the request to \(user.username)", call: FriendsAPI.removeRequest) {
			outgoingRequests.removeAll { $0.id == user.id }
		}
	}

	func unfriend(_ user: IdentifiableUserInfo) {
		runFriendAction(user, failure: "Couldn't unfriend \(user.username)", call: FriendsAPI.unfriend) {
			friends.removeAll { $0.id == user.id }
		}
	}

	func runFriendAction(_ user: IdentifiableUserInfo, failure: String, call: (Int, @escaping (KesselResult<Data>) -> Void) -> Void, onSuccess: @escaping () -> Void) {
		guard !friendBusy.contains(user.id) else { return }
		friendBusy.insert(user.id)
		call(user.id) { result in
			friendBusy.remove(user.id)
			switch result {
			case .ok:
				withAnimation { onSuccess() }
				refreshFriends()
			case .unauthorized:
				sessionExpired = true
			case .failed(let message):
				baseAlertText = "\(failure): \(message)"
				showBaseAlert = true
				refreshFriends()
			}
		}
	}

	func friendRow<Actions: View>(_ user: IdentifiableUserInfo, @ViewBuilder actions: () -> Actions) -> some View {
		HStack {
			AvatarView(userId: user.id, size: 48)
			Text("\(user.username)#\(String(user.id))")
				.font(.system(size: 16, weight: .medium))
				.lineLimit(1)
			Spacer()
			if friendBusy.contains(user.id) {
				ActivityIndicator(isAnimating: .constant(true), style: .medium, tint: UIColor(named: "Foreground") ?? .white)
					.frame(width: 44, height: 44)
			} else {
				actions()
			}
		}
		.padding(8)
		.background(Color("BackgroundCard"))
		.cornerRadius(12)
	}

	func promptBanner(_ text: String, button: String, action: @escaping () -> Void) -> some View {
		HStack {
			Text(text)
				.foregroundColor(Color("Foreground"))
			Spacer()
			Button(action: action) {
				Text(button)
					.fontWeight(.semibold)
					.foregroundColor(Color("AccentColor"))
					.frame(minWidth: 44, minHeight: 44)
					.contentShape(Rectangle())
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 2)
		.background(Rectangle().fill(Color("BackgroundPrompt")))
		.cornerRadius(8)
		.frame(maxWidth: 400)
	}

	func connectTo(_ who: IdentifiableHostInfo, retried: Bool = false, share: ShareSecret? = nil) {
		if let share = share {
			CParsec.shareSecret = share
		} else if CParsec.shareSecret?.peer != who.id {
			CParsec.shareSecret = nil
		}

		if NetworkWatcher.shared.noNetwork {
			appNote("[connect] no network, not trying")
			withAnimation {
				isConnecting = false
				waitingForApproval = false
				retryingConnect = false
			}
			baseAlertText = "No network connection"
			showBaseAlert = true
			return
		}

		if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
			let scale = window.screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(window.bounds.width * scale), height: Int(window.bounds.height * scale))
		} else {
			// no key window yet on a launch reconnect, without this it asks the host for 3840x2160
			let screen = UIScreen.main
			let scale = screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(screen.bounds.width * scale), height: Int(screen.bounds.height * scale))
		}

		pollTimer?.invalidate()
		pollTimer = nil
		CParsec.initialize()
		DataManager.model.reset()
		ParsecBackgroundManager.shared.reconnectAttempts = 0
		connectingToName = who.hostname
		retryingConnect = retried
		withAnimation { isConnecting = true }

		connectStartedAt = Date()
		let status = CParsec.connect(who.id)
		appNote("[connect] started, status \(status.rawValue)")
		connectPolls = 0
		approvalStartedAt = nil

		// Polling status
		pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
			MainActor.assumeIsolated {
				pollConnect(who)
			}
		}
	}

	func pollConnect(_ who: IdentifiableHostInfo) {
		let status = CParsec.getStatus()
		connectPolls += 1

		if let err = CParsec.setupError, err.at > connectStartedAt, status == PARSEC_CONNECTING || status == CONNECT_WRN_APPROVAL {
			CParsec.setupError = nil
			appNote("[connect] sdk setup failed after \(connectPolls) polls, retried \(retryingConnect): \(err.line)")
			retryOrGiveUp(who)
			return
		}

		if status == PARSEC_CONNECTING { return } // wait

		if status == CONNECT_WRN_APPROVAL {
			if approvalStartedAt == nil {
				appNote("[connect] status \(status.rawValue) after \(connectPolls) polls, retried \(retryingConnect)")
				if connectPolls >= 20 {
					retryOrGiveUp(who)
					return
				}
			}
			let started = approvalStartedAt ?? Date()
			approvalStartedAt = started
			if !waitingForApproval { withAnimation { waitingForApproval = true } }
			if Date().timeIntervalSince(started) < 60 { return }
		}

		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}
		appNote("[connect] result \(status.rawValue)")

		if status == PARSEC_OK {
			ParsecBackgroundManager.shared.connectionDidGoLive(peerId: who.id, hostname: hosts.first(where: { $0.id == who.id })?.hostname ?? who.hostname)
			if let c = controller {
				c.setView(.parsec)
			}
		} else {
			CParsec.disconnect()
			baseAlertText = status.readable(connecting: true)
			showBaseAlert = true
		}

		pollTimer?.invalidate()
	}

	func retryOrGiveUp(_ who: IdentifiableHostInfo) {
		pollTimer?.invalidate()
		CParsec.disconnect()
		if !retryingConnect {
			connectTo(who, retried: true)
			return
		}
		withAnimation {
			isConnecting = false
			retryingConnect = false
		}
		baseAlertText = "\(who.hostname) didn't answer the connection request"
		showBaseAlert = true
	}

	func cancelConnection() {
		appNote("[connect] cancelled")
		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}

		CParsec.disconnect()

		pollTimer?.invalidate()
	}

	func logout() {
		removeFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey)
		NetworkHandler.clinfo = nil
		ParsecBackgroundManager.shared.disableAutoReconnect()
		if let c = controller {
			c.setView(.login)
		}
	}

	func removeFromKeychain(key: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
		let status = SecItemDelete(query as CFDictionary)
		if status == errSecSuccess {
			print("Successfully removed data from keychain.")
		}
	}
}

struct MainView_Previews: PreviewProvider {
	static var previews: some View {
		MainView(nil)
	}
}

struct IdentifiableHostInfo: Identifiable {
	var id: String // Peer ID
	var hostname: String // Computer's Display Name
	var user: UserInfo // User Data
	var connections: Int // User's Connected To This Host
}

struct IdentifiableUserInfo: Identifiable {
	var id: Int // User ID
	var username: String // User Display Name
}

private enum Page {
	case hosts
	case friends
}

struct AvatarView: View {
	var userId: Int
	var size: CGFloat

	var body: some View {
		URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=\(Int(size)),h=\(Int(size)),fit=crop,background=white,q=90,f=jpeg/avatars/\(String(userId))/avatar"),
			output:
			{
				$0
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: size, height: size)
					.cornerRadius(6)
			},
			placeholder:
			{
				Image("IconTransparent")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: size, height: size)
					.background(Rectangle().fill(Color("BackgroundPrompt")))
					.cornerRadius(6)
			})
	}
}

struct JoinLinkView: View {
	var onConnect: (IdentifiableHostInfo, ShareSecret?) -> Void

	@Environment(\.presentationMode) var presentationMode

	@State private var text = ""
	@State private var method = SecretMethod.saved
	@State private var looking = false
	@State private var host: PublicHost?
	@State private var lookupError: String?
	@State private var lookedUpFor: String?

	private var parsed: (peer: String, secret: String?)? { ShareLink.parse(text) }

	var body: some View {
		NavigationView {
			ZStack {
				Color("BackgroundGray")
					.edgesIgnoringSafeArea(.all)
				ScrollView(.vertical) {
					VStack(alignment: .leading, spacing: 12) {
						Text("Share link or Peer ID")
							.font(.system(size: 14, weight: .medium))
							.opacity(0.7)
						HStack(spacing: 8) {
							TextField("https://parsec.gg/g/...", text: $text, onCommit: lookUp)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.keyboardType(.URL)
								.padding(.horizontal, 12)
								.frame(minHeight: 44)
								.background(Color("BackgroundPrompt"))
								.cornerRadius(8)
							Button(action: pasteFromClipboard) {
								Text("Paste")
									.lineLimit(1)
									.fixedSize()
									.foregroundColor(Color("AccentColor"))
									.padding(.horizontal, 12)
									.frame(minHeight: 44)
									.background(Color("BackgroundPrompt"))
									.cornerRadius(8)
							}
						}

						if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed == nil {
							Text("This doesn't look like a Parsec share link. It should look like https://parsec.gg/g/…")
								.font(.system(size: 13))
								.opacity(0.7)
								.fixedSize(horizontal: false, vertical: true)
						}

						if let p = parsed {
							VStack(alignment: .leading, spacing: 8) {
								if looking {
									HStack(spacing: 8) {
										ActivityIndicator(isAnimating: .constant(true), style: .medium, tint: UIColor(named: "Foreground") ?? .white)
											.frame(width: 20, height: 20)
										Text("Checking the link...")
									}
								} else if let host = host {
									HStack {
										AvatarView(userId: host.user.id, size: 48)
										VStack(alignment: .leading, spacing: 2) {
											Text(host.name)
												.font(.system(size: 16, weight: .medium))
												.lineLimit(1)
											Text("\(host.user.name)#\(String(host.user.id)) invited you")
												.font(.system(size: 13))
												.opacity(0.6)
												.lineLimit(1)
										}
										Spacer()
									}
								} else if let lookupError = lookupError {
									Text(lookupError)
										.fixedSize(horizontal: false, vertical: true)
								}
								if p.secret == nil {
									Text("No secret in this link, so the host will need to approve you or have given you access.")
										.font(.system(size: 13))
										.opacity(0.6)
										.fixedSize(horizontal: false, vertical: true)
								}
								Button(action: connect) {
									Text(host == nil ? "Connect Anyway" : "Connect to \(host!.name)")
										.lineLimit(1)
										.foregroundColor(.white)
										.padding(.horizontal, 20)
										.frame(maxWidth: .infinity, minHeight: 44)
										.background(Color("AccentColor"))
										.cornerRadius(8)
								}
								.disabled(looking)
								.padding(.top, 4)
							}
							.padding(12)
							.background(Color("BackgroundCard"))
							.cornerRadius(12)
						}

						if parsed?.secret != nil {
							VStack(alignment: .leading, spacing: 6) {
								Text("Secret method (testing)")
									.font(.system(size: 13, weight: .medium))
									.opacity(0.7)
								Picker("Secret method", selection: $method) {
									ForEach(SecretMethod.allCases, id: \.self) { m in
										Text(m.rawValue).tag(m)
									}
								}
								.pickerStyle(SegmentedPickerStyle())
								Text("How the link's secret is passed to Parsec. If Config doesn't let you in, try Peer string. Turn on Show Connection Log in Settings to see which one was used.")
									.font(.system(size: 12))
									.opacity(0.5)
									.fixedSize(horizontal: false, vertical: true)
							}
							.padding(.top, 8)
						}
					}
					.padding()
					.frame(maxWidth: 500)
					.frame(maxWidth: .infinity)
				}
			}
			.navigationBarTitle("Join with Link", displayMode: .inline)
			.navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() })
		}
		.navigationViewStyle(StackNavigationViewStyle())
		.foregroundColor(Color("Foreground"))
		.accentColor(Color("AccentColor"))
		.onChange(of: text) { _ in
			if parsed?.peer != lookedUpFor {
				host = nil
				lookupError = nil
				looking = false
				lookedUpFor = nil
				lookUp()
			}
		}
	}

	func pasteFromClipboard() {
		if let s = UIPasteboard.general.string {
			text = s.trimmingCharacters(in: .whitespacesAndNewlines)
		}
	}

	func lookUp() {
		guard let p = parsed, p.peer != lookedUpFor else { return }
		lookedUpFor = p.peer
		looking = true
		ShareLink.lookup(peer: p.peer, secret: p.secret) { result in
			guard lookedUpFor == p.peer else { return }
			looking = false
			switch result {
			case .ok(let h):
				host = h
				lookupError = nil
			case .unauthorized:
				lookupError = "Couldn't check the link. You can still try to connect."
			case .failed(let message):
				lookupError = message
			}
		}
	}

	func connect() {
		guard let p = parsed else { return }
		SecretMethod.saved = method
		let user = UserInfo(id: host?.user.id ?? 0, name: host?.user.name ?? "", warp: false, team_id: "")
		let info = IdentifiableHostInfo(id: p.peer, hostname: host?.name ?? "shared host", user: user, connections: 0)
		let share = p.secret.map { ShareSecret(peer: p.peer, secret: $0, method: method) }
		appNote("[link] joining from a share link, secret \(p.secret == nil ? "missing" : "present"), method \(method.rawValue)")
		onConnect(info, share)
	}
}

struct AddFriendView: View {
	var onChange: () -> Void
	var onUnauthorized: () -> Void

	@Environment(\.presentationMode) var presentationMode

	@State private var query = ""
	@State private var results: [UserSearchResult] = []
	@State private var searchedFor: String?
	@State private var searching = false
	@State private var error: String?
	@State private var notice: String?
	@State private var sentIds: Set<Int> = []
	@State private var sendingId: Int?

	private var canSearch: Bool {
		!query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !searching
	}

	var body: some View {
		NavigationView {
			ZStack {
				Color("BackgroundGray")
					.edgesIgnoringSafeArea(.all)
				ScrollView(.vertical) {
					VStack(alignment: .leading, spacing: 12) {
						Text("Name#ID or name")
							.font(.system(size: 14, weight: .medium))
							.opacity(0.7)
						HStack(spacing: 8) {
							TextField("e.g. DuckyTura#12922926", text: $query, onCommit: search)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.padding(.horizontal, 12)
								.frame(minHeight: 44)
								.background(Color("BackgroundPrompt"))
								.cornerRadius(8)
							Button(action: search) {
								Text("Search")
									.lineLimit(1)
									.fixedSize()
									.foregroundColor(.white)
									.padding(.horizontal, 16)
									.frame(minHeight: 44)
									.background(Color("AccentColor"))
									.cornerRadius(8)
							}
							.disabled(!canSearch)
							.opacity(canSearch ? 1 : 0.4)
						}
						Text("The ID is the number after # in their Parsec name. With an ID, the request goes to exactly that person.")
							.font(.system(size: 13))
							.opacity(0.5)
							.fixedSize(horizontal: false, vertical: true)

						if searching {
							HStack(spacing: 8) {
								ActivityIndicator(isAnimating: .constant(true), style: .medium, tint: UIColor(named: "Foreground") ?? .white)
									.frame(width: 20, height: 20)
								Text("Searching...")
							}
						}
						if let error = error {
							Text(error)
								.foregroundColor(Color("Foreground"))
								.padding(12)
								.frame(maxWidth: .infinity, alignment: .leading)
								.background(Color("BackgroundPrompt"))
								.cornerRadius(8)
						}
						if let notice = notice {
							HStack(spacing: 8) {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
								Text(notice)
									.fixedSize(horizontal: false, vertical: true)
							}
							.padding(12)
							.frame(maxWidth: .infinity, alignment: .leading)
							.background(Color("BackgroundCard"))
							.cornerRadius(8)
						}

						ForEach(results) { r in
							HStack {
								AvatarView(userId: r.id, size: 48)
								Text(label(r))
									.font(.system(size: 16, weight: .medium))
									.lineLimit(1)
								Spacer()
								resultAction(r)
							}
							.padding(8)
							.background(Color("BackgroundCard"))
							.cornerRadius(12)
						}

						if let searchedFor = searchedFor, results.isEmpty, !searching, error == nil {
							Text("No one named \"\(searchedFor)\". Check the spelling, or enter their Name#ID.")
								.opacity(0.6)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
					.padding()
					.frame(maxWidth: 500)
					.frame(maxWidth: .infinity)
				}
			}
			.navigationBarTitle("Add Friend", displayMode: .inline)
			.navigationBarItems(trailing: Button("Done") { presentationMode.wrappedValue.dismiss() })
		}
		.navigationViewStyle(StackNavigationViewStyle())
		.foregroundColor(Color("Foreground"))
		.accentColor(Color("AccentColor"))
	}

	func label(_ r: UserSearchResult) -> String {
		r.name.isEmpty ? "User #\(String(r.id))" : "\(r.name)#\(String(r.id))"
	}

	@ViewBuilder
	func resultAction(_ r: UserSearchResult) -> some View {
		if sendingId == r.id {
			ActivityIndicator(isAnimating: .constant(true), style: .medium, tint: UIColor(named: "Foreground") ?? .white)
				.frame(width: 44, height: 44)
		} else if r.is_friend == true {
			Text("Friends")
				.opacity(0.5)
				.padding(.horizontal, 8)
		} else if r.is_friend_requested == true || sentIds.contains(r.id) {
			Text("Requested")
				.opacity(0.5)
				.padding(.horizontal, 8)
		} else {
			Button(action: { send(r) }) {
				Text("Send Request")
					.lineLimit(1)
					.fixedSize()
					.foregroundColor(.white)
					.padding(.horizontal, 12)
					.frame(minHeight: 44)
					.background(Color("AccentColor"))
					.cornerRadius(8)
			}
			.disabled(sendingId != nil)
		}
	}

	func search() {
		let tag = FriendsAPI.parseUserTag(query)
		guard !tag.name.isEmpty || tag.id != nil, !searching else { return }
		error = nil
		notice = nil

		// Only a number: Parsec can't look it up, so offer it as is.
		if tag.name.isEmpty, let id = tag.id {
			results = [UserSearchResult(id: id, name: "", is_friend: nil, is_friend_requested: nil)]
			searchedFor = nil
			return
		}

		searching = true
		FriendsAPI.search(tag.name) { result in
			searching = false
			switch result {
			case .ok(let list):
				if let id = tag.id {
					let match = list.filter { $0.id == id }
					// Not in the name results (search only returns the first matches), still sendable by id.
					results = match.isEmpty ? [UserSearchResult(id: id, name: tag.name, is_friend: nil, is_friend_requested: nil)] : match
					searchedFor = nil
				} else {
					results = list
					searchedFor = tag.name
				}
			case .unauthorized:
				onUnauthorized()
				error = "Your Parsec session expired. Close this and sign in again."
			case .failed(let message):
				error = "Couldn't search: \(message)"
			}
		}
	}

	func send(_ r: UserSearchResult) {
		guard sendingId == nil else { return }
		sendingId = r.id
		error = nil
		notice = nil
		FriendsAPI.sendRequest(r.id) { result in
			sendingId = nil
			switch result {
			case .ok:
				sentIds.insert(r.id)
				notice = "Request sent to \(label(r)). You'll be friends once they accept."
				onChange()
			case .unauthorized:
				onUnauthorized()
				error = "Your Parsec session expired. Close this and sign in again."
			case .failed(let message):
				error = "Couldn't send the request to \(label(r)): \(message)"
			}
		}
	}
}
