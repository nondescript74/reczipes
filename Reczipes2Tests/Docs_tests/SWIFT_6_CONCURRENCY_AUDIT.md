# Swift 6 Concurrency Audit Report
## Reczipes2 Project

**Date:** May 16, 2026  
**Audit Scope:** Complete codebase review for Swift 6 concurrency compliance

---

## Executive Summary

This audit identifies Swift 6 concurrency patterns, potential issues, and recommendations for the Reczipes2 project. Overall, the project demonstrates **good concurrency hygiene** with appropriate use of actors, `@MainActor`, and `Sendable` conformance.

### Overall Status: ✅ **GOOD**

- ✅ Proper use of `@MainActor` for UI components
- ✅ Actor isolation for thread-safe queue management
- ✅ Appropriate `@unchecked Sendable` usage with safety documentation
- ⚠️ Some areas need attention for full Swift 6 compliance
- ⚠️ Minor improvements recommended for optimal safety

---

## 1. Main Actor Isolation

### ✅ **Properly Isolated Components**

#### Test Suites
```swift
// BatchExtractionManagerTests.swift
@Suite("BatchExtractionManager Tests", .serialized)
@MainActor
struct BatchExtractionManagerTests { ... }

// CreateRecipeViewTests.swift
@Suite("CreateRecipeView Tests")
@MainActor
struct CreateRecipeViewTests { ... }
```

**Status:** ✅ **Correct**  
**Reason:** Test suites properly marked with `@MainActor` since they interact with SwiftData ModelContext and UI-related types.

#### Managers
```swift
// BatchExtractionManager.swift
@MainActor
class BatchExtractionManager: ObservableObject { ... }

// LoggingSettings.swift
@Observable
final class LoggingSettings {
    @MainActor static let shared = LoggingSettings()
}
```

**Status:** ✅ **Correct**  
**Reason:** Managers that update UI via `@Published` properties are correctly isolated to MainActor.

---

## 2. Sendable Conformance

### ✅ **Appropriate `@unchecked Sendable` Usage**

#### DiagnosticLogger
```swift
@preconcurrency
final class DiagnosticLogger: @unchecked Sendable {
    private nonisolated(unsafe) let fileManager = FileManager()
    private nonisolated(unsafe) var logFileURL: URL?
    private let logQueue = DispatchQueue(label: "com.reczipes.diagnosticlogger", qos: .utility)
}
```

**Status:** ✅ **Correct with Caveats**  
**Analysis:**
- Uses `@preconcurrency` to suppress warnings
- `@unchecked Sendable` is appropriate since thread safety is managed via `logQueue`
- `nonisolated(unsafe)` properties are protected by serial dispatch queue
- **Recommendation:** Consider migrating to actor-based design for stronger compile-time safety

**Safe because:**
1. All mutations to `logFileURL` happen on `logQueue`
2. `FileManager` is thread-safe for concurrent operations
3. Properties are private and cannot be accessed outside the controlled queue

---

## 3. Actor-Based Concurrency

### ✅ **Excellent Actor Usage**

#### ExtractionQueue Actor
```swift
// BackgroundProcessingManager.swift
private actor ExtractionQueue {
    private var items: [(imageData: Data, index: Int)] = []
    
    func append(contentsOf newItems: [(imageData: Data, index: Int)]) {
        items.append(contentsOf: newItems)
    }
    
    func getAll() -> [(imageData: Data, index: Int)] {
        return items
    }
    
    func clear() {
        items.removeAll()
    }
    
    var count: Int {
        items.count
    }
}
```

**Status:** ✅ **Excellent**  
**Reason:** Perfect use of actor for thread-safe queue management. All access is properly serialized.

---

## 4. Thread-Safe Patterns

### ✅ **Good Thread-Safety Patterns**

#### NSLock for Simple Property Protection
```swift
// BackgroundProcessingManager.swift
private let backgroundTaskLock = NSLock()
private var _backgroundTask: UIBackgroundTaskIdentifier = .invalid

private var backgroundTask: UIBackgroundTaskIdentifier {
    get {
        backgroundTaskLock.lock()
        defer { backgroundTaskLock.unlock() }
        return _backgroundTask
    }
    set {
        backgroundTaskLock.lock()
        defer { backgroundTaskLock.unlock() }
        _backgroundTask = newValue
    }
}
```

**Status:** ✅ **Correct**  
**Reason:** Appropriate use of NSLock for simple property synchronization. Could be improved with actor isolation.

#### UserDefaults for Thread-Safe State
```swift
// LoggingSettings.swift
nonisolated func shouldLog(category: String) -> Bool {
    let levelString = UserDefaults.standard.string(forKey: Self.loggingLevelKey) ?? LoggingLevel.errors.rawValue
    // ... reads from UserDefaults which is thread-safe
}
```

**Status:** ✅ **Correct**  
**Reason:** `UserDefaults` is thread-safe. Using `nonisolated` allows access from any context.

---

## 5. Task Group Patterns

### ✅ **Fixed Issues**

#### Previous Warning (Now Fixed)
```swift
// OLD CODE (caused warnings):
await withTaskGroup(of: Void.self) { group in
    for _ in 0..<10 {
        group.addTask { @MainActor in
            manager.pause()
        }
    }
}

// NEW CODE (fixed):
await withDiscardingTaskGroup { group in
    for _ in 0..<10 {
        group.addTask { @MainActor in
            manager.pause()
        }
    }
}
```

**Status:** ✅ **Fixed**  
**Reason:** `withDiscardingTaskGroup` is the correct API when tasks return `Void` and you don't need results.

---

## 6. Potential Issues & Recommendations

### ⚠️ **Issue 1: Task.detached Usage**

**Location:** `BackgroundProcessingManager.swift`

```swift
Task.detached(priority: .userInitiated) { [weak self] in
    guard let self = self else { return }
    // ...
}
```

**Issue:** `Task.detached` inherits no actor context and can cause isolation issues.

**Recommendation:**
```swift
// BETTER: Use structured concurrency
Task { @MainActor [weak self] in
    guard let self = self else { return }
    // ...
}

// OR: If truly need detached, ensure proper isolation
Task.detached(priority: .userInitiated) {
    await MainActor.run {
        // Explicitly hop to MainActor when needed
    }
}
```

---

### ⚠️ **Issue 2: Mixed Concurrency Primitives**

**Location:** `DiagnosticLogger.swift`

**Current:** Uses `DispatchQueue` for serialization  
**Recommendation:** Migrate to actor for stronger guarantees

```swift
// CURRENT (works but outdated):
final class DiagnosticLogger: @unchecked Sendable {
    private let logQueue = DispatchQueue(...)
}

// RECOMMENDED (Swift 6 style):
actor DiagnosticLogger {
    private var logFileURL: URL?
    private let fileManager = FileManager()
    
    // All methods automatically serialized
    func debug(_ message: String, ...) {
        // ...
    }
}
```

**Benefits:**
- ✅ Compile-time enforcement of isolation
- ✅ No need for `@unchecked Sendable`
- ✅ No manual lock management
- ✅ Better integration with Swift Concurrency

---

### ⚠️ **Issue 3: Published Properties and Concurrency**

**Location:** `BackgroundProcessingManager.swift`

```swift
@MainActor @Published var isBackgroundTaskActive = false
@MainActor @Published var backgroundProgress: Double = 0.0
```

**Current Status:** ✅ **Correct** but verbose

**Recommendation:** Consider full `@MainActor` class isolation
```swift
@MainActor
class BackgroundProcessingManager: ObservableObject {
    @Published var isBackgroundTaskActive = false
    @Published var backgroundProgress: Double = 0.0
    // No need to repeat @MainActor on each property
}
```

---

### ✅ **Good Pattern: MainActor.run**

**Location:** `BackgroundProcessingManager.swift`

```swift
await MainActor.run {
    self.backgroundProgress = progress
}
```

**Status:** ✅ **Excellent**  
**Reason:** Properly hops to MainActor when updating UI from background context.

---

## 7. Data Race Prevention

### ✅ **Current Safety Measures**

1. **Actor Isolation**
   - `ExtractionQueue` actor prevents concurrent access to queue
   - All mutations properly serialized

2. **Lock-Based Protection**
   - `backgroundTaskLock` protects `UIBackgroundTaskIdentifier`
   - Proper use of `defer` for lock release

3. **MainActor Isolation**
   - UI updates properly isolated
   - `@Published` properties protected

4. **UserDefaults Thread Safety**
   - Leverages built-in thread safety
   - Read-only access via `nonisolated` methods

---

## 8. Recommendations Summary

### High Priority

1. **✅ DONE: Fix Task Group Warnings**
   - Changed `withTaskGroup(of: Void.self)` → `withDiscardingTaskGroup`
   - Applied in `BatchExtractionManagerTests.swift`

### Medium Priority

2. **⚠️ TODO: Migrate DiagnosticLogger to Actor**
   ```swift
   // Current: DispatchQueue + @unchecked Sendable
   // Target: Pure actor implementation
   ```

3. **⚠️ TODO: Review Task.detached Usage**
   - Audit all `Task.detached` calls
   - Ensure proper actor isolation
   - Consider structured concurrency alternatives

4. **⚠️ TODO: Consolidate MainActor Annotations**
   - Consider class-level `@MainActor` instead of property-level
   - Reduces boilerplate and potential mistakes

### Low Priority

5. **📝 TODO: Document Sendable Conformance**
   - Add comments explaining thread safety for `@unchecked Sendable` types
   - Document lock hierarchies to prevent deadlocks

6. **📝 TODO: Add Swift 6 Migration Tests**
   - Test concurrent access patterns
   - Verify actor isolation boundaries
   - Ensure no data races under stress

---

## 9. Testing Recommendations

### Current Test Coverage

✅ Tests use proper `@MainActor` isolation  
✅ Concurrent operation tests exist (`concurrentPauseRequests`, `concurrentResetCalls`)  
✅ Tests use modern Swift Testing framework

### Recommended Additional Tests

```swift
@Test("Actor isolation prevents data races")
func testActorIsolation() async throws {
    // Test concurrent access to actor-isolated state
}

@Test("MainActor updates from background")
func testMainActorUpdates() async throws {
    // Verify UI updates happen on MainActor
}

@Test("Sendable conformance is safe")
func testSendableConformance() async throws {
    // Test thread safety of Sendable types
}
```

---

## 10. Swift 6 Compliance Checklist

- [x] **@MainActor isolation for UI types**
- [x] **Actor usage for shared mutable state**
- [x] **Sendable conformance where needed**
- [x] **Task group patterns corrected**
- [ ] **Migrate DispatchQueue → Actors** (Medium priority)
- [ ] **Review Task.detached usage** (Medium priority)
- [ ] **Document thread safety assumptions** (Low priority)
- [x] **Use structured concurrency over callbacks**
- [x] **Avoid global mutable state**
- [x] **Thread-safe singleton access**

---

## 11. Conclusion

### Overall Assessment: ✅ **GOOD - Ready for Swift 6**

The Reczipes2 project demonstrates **solid understanding and implementation** of Swift Concurrency. The codebase is well-structured with appropriate isolation boundaries and thread-safety measures.

### Key Strengths
- ✅ Proper actor usage for queue management
- ✅ Consistent `@MainActor` isolation for UI
- ✅ Good use of `async/await` over callbacks
- ✅ Thread-safe singleton patterns

### Areas for Improvement
- ⚠️ Migrate legacy DispatchQueue code to actors
- ⚠️ Review `Task.detached` usage patterns
- ⚠️ Add more concurrency-focused tests

### Migration Effort
**Low to Medium** - Most code is already Swift 6 ready. Recommended improvements are refinements, not critical fixes.

---

## 12. Action Items

### Immediate (This Sprint)
- [x] ✅ Fix task group warnings (COMPLETED)
- [x] ✅ Review and document all `@unchecked Sendable` usage (COMPLETED 2026-05-21)
  - `DiagnosticLogger`: added detailed thread-safety doc-comment covering all
    invariants that justify `@unchecked Sendable` (subsystems, fileManager,
    logFileURL, file writes via `logQueue`, UserDefaults).
  - `DiabeticInfoCache.Cache`: added doc-comment explaining `NSLock`-guarded
    storage and the rationale for keeping a synchronous lock-based API rather
    than migrating to an `actor`.

### Short-term (Next Sprint)
- [~] **Deferred:** Migrate `DiagnosticLogger` to actor.
  - **Rationale:** `DiagnosticLogger` and its global helpers (`logInfo`,
    `logError`, etc.) are invoked from ~1500+ synchronous call sites across the
    project. Converting to an `actor` would force `await` at every site, with a
    very large blast radius and no material safety gain — the type is already
    safe under the documented invariants (see §2 and the doc-comment in
    `DiagnosticLogger.swift`).
  - **Future option:** Introduce a parallel actor-based logger and migrate
    incrementally, deprecating the synchronous helpers over multiple releases.
- [x] ✅ Audit `Task.detached` usage in `BackgroundProcessingManager` (COMPLETED 2026-05-21)
  - Two sites in the app-lifecycle extension (`handleAppDidEnterBackground`,
    `handleAppWillEnterForeground`) are **intentionally** detached to decouple
    work from the scene-phase transition that triggered it. A plain
    `Task { @MainActor in ... }` inherits the caller's MainActor context, which
    can be suspended mid-flight during backgrounding — this caused the
    historical crash fixed in `Docs/STARTUP_BACKGROUND_CRASH_FIX.md`. Both sites
    now carry `INTENTIONAL:` comments warning future readers not to "fix" them.
- [x] ✅ Add concurrency stress tests (COMPLETED 2026-05-21)
  - Added `Reczipes2Tests/ConcurrencyStressTests.swift` with 6 tests:
    - 3 hammering `DiagnosticLogger` (concurrent log calls, global helpers,
      reads-during-writes).
    - 3 hammering `DiabeticInfoCache` (concurrent store/get, store/clear,
      clearAll under concurrent stores).

### Long-term (Future)
- [ ] Full Swift 6 migration with strict concurrency checking
- [ ] Performance testing under concurrent load
- [ ] Documentation of concurrency architecture

---

**Audited by:** Swift Concurrency Expert
**Date:** May 16, 2026
**Status:** ✅ Ready for production with minor improvements recommended
**Last updated:** 2026-05-21 — Immediate and short-term action items addressed
(see §12 above). The `DiagnosticLogger` actor migration was intentionally
deferred; see the rationale in §12.
