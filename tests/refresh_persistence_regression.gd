extends SceneTree
## Disposable API and token file only. Never prints credentials.

var failures: int = 0
var session: ResceneAuthSession

func _initialize() -> void:
	call_deferred("verify")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func verify() -> void:
	session = GameServices.session()
	var mode: String = OS.get_environment("RESCENE_AUTH_TEST_MODE")
	if OS.get_environment("RESCENE_AUTH_FILE").is_empty(): push_error("Isolated token file required."); quit(1); return
	match mode:
		"seed":
			var response: Dictionary = await session.authenticate("refresh_" + str(Time.get_ticks_usec()), "test password!", true, true)
			check(StrictData.boolean(response.ok), "Registration creates a persistent session")
			check(session._refresh_token.length() == 43 and session._refresh_expires_at - StrictData.integer(Time.get_unix_time_from_system()) >= 2591990, "Refresh session lasts thirty days")
			check(FileAccess.file_exists(session.session_file()), "Credentials saved for the next process")
		"restore", "restore_expired_access", "restore_lost_response", "restore_after_server_restart":
			var saved: Dictionary = saved_session()
			var prior: String = str(saved.get("refresh_token", ""))
			var response: Dictionary = await session.restore_session()
			check(StrictData.boolean(response.ok and session.is_authenticated()), "New process restores through the refresh endpoint")
			check(session._refresh_token != prior and session._refresh_token.length() == 43, "Returning to the game rotates and renews the saved refresh token")
			check(session._refresh_expires_at - StrictData.integer(Time.get_unix_time_from_system()) >= 2591990, "Returning session receives thirty days")
		"exercise":
			var restored: Dictionary = await session.restore_session()
			check(StrictData.boolean(restored.ok), "Restore before exercising online refresh")
			var previous: String = session._refresh_token
			session._expires_at_ms = Time.get_ticks_msec() - 1
			var response: Dictionary = await session.fetch_profile()
			check(StrictData.boolean(response.ok and session.is_authenticated()), "Protected request refreshes expired access automatically")
			check(previous != session._refresh_token, "Automatic refresh rotates the credential")
			previous = session._refresh_token
			var login: Dictionary = await session.authenticate(str(session.user.username), "test password!")
			check(StrictData.boolean(login.ok and session._refresh_token != previous), "Password login always renews refresh credentials")
			# A 401 received before the local timer expires also refreshes and retries.
			session._token = "invalid-access"
			response = await session.fetch_profile()
			check(StrictData.boolean(response.ok and session.is_authenticated()), "Server-rejected access JWT refreshes and retries the original request")
			# Several requests hit the expired JWT together; only the first rotates.
			previous = session._refresh_token
			session._expires_at_ms = Time.get_ticks_msec() - 1
			_concurrent_profiles.call_deferred()
			response = await session.fetch_profile()
			await create_timer(0.2).timeout
			check(StrictData.boolean(response.ok and session._refresh_token != previous), "Concurrent protected calls survive access expiry")
			# Startup-independent periodic refresh handles gameplay with no HTTP calls.
			previous = session._refresh_token
			session._expires_at_ms = Time.get_ticks_msec() - 1
			for step: int in 100:
				if session._refresh_token != previous: break
				await create_timer(0.05).timeout
			check(session._refresh_token != previous and session.is_authenticated(), "Background renewal keeps active gameplay signed in")
			var origin: String = OS.get_environment("RESCENE_API_URL")
			previous = session._refresh_token
			OS.set_environment("RESCENE_API_URL", "http://127.0.0.1:59999")
			session._expires_at_ms = Time.get_ticks_msec() - 1
			response = await session.fetch_profile()
			check(StrictData.boolean(not response.ok and session.is_authenticated() and session._refresh_token == previous), "Transient refresh outage preserves the active account and credential")
			OS.set_environment("RESCENE_API_URL", origin)
			response = await session.fetch_profile()
			check(StrictData.boolean(response.ok and session._refresh_token != previous), "Connection recovery renews without another password")
		"prepare_lost_response":
			var restored: Dictionary = await session.restore_session()
			check(StrictData.boolean(restored.ok), "Restore before lost refresh response")
			var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
			session._refresh_request_id = id
			check(session._save_session(), "Pending refresh ID is durable before HTTP")
			var response: Dictionary = await session._http("/api/v1/auth/refresh", HTTPClient.METHOD_POST, {"refresh_token":session._refresh_token,"request_id":id})
			check(StrictData.boolean(response.ok), "Server rotates before a simulated response loss")
			# Deliberately do not accept/save the response; next process must recover it.
		"offline":
			var previous: String = FileAccess.get_file_as_string(session.session_file())
			var response: Dictionary = await session.restore_session()
			check(StrictData.boolean(not response.ok and not session.is_authenticated()), "Offline startup does not pretend to be verified")
			check(FileAccess.file_exists(session.session_file()), "Offline refresh retains credentials for retry")
			check(not previous.is_empty(), "Offline fixture contains a saved session")
		"expire_refresh", "invalid":
			var response: Dictionary = await session.restore_session()
			check(StrictData.boolean(not response.ok and not session.is_authenticated()), "Expired or invalid refresh requires login")
			check(not FileAccess.file_exists(session.session_file()), "Rejected saved credentials are removed")
		"logout":
			var restored: Dictionary = await session.restore_session()
			check(StrictData.boolean(restored.ok), "Restore before logout")
			var token: String = session._refresh_token
			session.logout()
			check(not session.is_authenticated() and not FileAccess.file_exists(session.session_file()), "Logout clears memory and disk immediately")
			await create_timer(0.2).timeout
			while session.busy: await process_frame
			var response: Dictionary = await session._http("/api/v1/auth/refresh", HTTPClient.METHOD_POST, {"refresh_token":token,"request_id":Crypto.new().generate_random_bytes(16).hex_encode()})
			check(StrictData.integer(response.get("status",0)) == 401, "Logout revokes the refresh token on the server")
		"legacy":
			var login: Dictionary = await session.authenticate("legacy_" + str(Time.get_ticks_usec()), "test password!", true, true)
			check(StrictData.boolean(login.ok), "Legacy fixture registration")
			var legacy: String = session._token
			var file: FileAccess = FileAccess.open(session.session_file(), FileAccess.WRITE)
			var stored: bool = file.store_string(legacy)
			file.close()
			check(stored, "Legacy JWT text file saved")
			# Clear memory without revoking/deleting the legacy file.
			session.user = {}
			session._token = ""
			session._refresh_token = ""
			var response: Dictionary = await session.restore_session()
			check(StrictData.boolean(response.ok and session._refresh_token.length() == 43), "Still-valid old JWT upgrades automatically to thirty-day persistence")
		_:
			check(false,"Unknown persistence mode")
	if session.busy:
		while session.busy: await process_frame
	print("Refresh persistence (",mode,"): ","PASS" if failures == 0 else "FAIL")
	quit(failures)

func _concurrent_profiles() -> void:
	var response: Dictionary = await session.fetch_profile()
	check(StrictData.boolean(response.ok), "Concurrent request waits for the same refreshed session")

func saved_session() -> Dictionary:
	return StrictData.dictionary(JSON.parse_string(FileAccess.get_file_as_string(session.session_file())))
