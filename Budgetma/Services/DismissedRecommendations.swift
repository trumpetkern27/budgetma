import Foundation

/* --- Silenced recommendations ---
 * "yes, I know, I meant to do that"
 *
 * a recommendation you've considered and rejected is worse than useless on the
 * next visit: it trains you to ignore the whole section. so they can be
 * silenced individually, and stay silenced.
 *
 * stored in UserDefaults rather than as a @Model on purpose. it's a handful of
 * strings, it isn't budget data, and it doesn't deserve a schema migration —
 * losing it would cost you one dismissal, not a record of your money.
 *
 * recommendation ids are derived from the thing they're about (the expected
 * item, or the normalised name of the repeating spend), not from the numbers,
 * so a dismissal survives the underlying figures drifting a little.
 */
nonisolated enum DismissedRecommendations {
	static let key = "dismissedRecommendations"

	static var all: Set<String> {
		guard
			let raw = UserDefaults.standard.string(forKey: key),
			let data = raw.data(using: .utf8),
			let list = try? JSONDecoder().decode([String].self, from: data)
		else { return [] }
		return Set(list)
	}

	static func contains(_ id: String) -> Bool { all.contains(id) }

	static func dismiss(_ id: String) {
		write(all.union([id]))
	}

	static func restore(_ id: String) {
		write(all.subtracting([id]))
	}

	static func restoreAll() {
		write([])
	}

	private static func write(_ ids: Set<String>) {
		guard
			let data = try? JSONEncoder().encode(Array(ids).sorted()),
			let raw = String(data: data, encoding: .utf8)
		else { return }
		UserDefaults.standard.set(raw, forKey: key)
	}
}
