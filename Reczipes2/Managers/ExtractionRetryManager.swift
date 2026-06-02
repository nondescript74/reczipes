//
//  ExtractionRetryManager.swift
//  Reczipes2
//
//  Provides resilient retry logic for recipe extraction
//  Handles network failures, rate limiting, and transient errors
//

import Foundation

/// Manages retry logic for recipe extraction operations
actor ExtractionRetryManager {
    
    // MARK: - Configuration
    
    /// Configuration for retry behavior
    struct RetryConfiguration {
        /// Maximum number of retry attempts
        let maxAttempts: Int
        
        /// Initial delay before first retry (in seconds)
        let initialDelay: TimeInterval
        
        /// Maximum delay between retries (in seconds)
        let maxDelay: TimeInterval
        
        /// Multiplier for exponential backoff
        let backoffMultiplier: Double
        
        /// Whether to use jitter to avoid thundering herd
        let useJitter: Bool
        
        static let `default` = RetryConfiguration(
            maxAttempts: 3,
            initialDelay: 2.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0,
            useJitter: true
        )
        
        static let aggressive = RetryConfiguration(
            maxAttempts: 5,
            initialDelay: 1.0,
            maxDelay: 60.0,
            backoffMultiplier: 2.5,
            useJitter: true
        )
        
        static let conservative = RetryConfiguration(
            maxAttempts: 2,
            initialDelay: 5.0,
            maxDelay: 15.0,
            backoffMultiplier: 2.0,
            useJitter: false
        )
    }
    
    // MARK: - Error Classification
    
    /// Classifies errors to determine retry strategy
    enum ErrorClassification {
        case retryable          // Can retry immediately or with backoff
        case retryableAfterDelay(TimeInterval)  // Retry after specific delay (e.g., rate limit)
        case terminal           // Don't retry (e.g., 404, invalid data)
        
        var shouldRetry: Bool {
            switch self {
            case .retryable, .retryableAfterDelay:
                return true
            case .terminal:
                return false
            }
        }
    }
    
    // MARK: - Retry State
    
    private var retryHistory: [String: [Date]] = [:]
    
    // MARK: - Public API
    
    /// Execute an operation with automatic retry logic
    /// - Parameters:
    ///   - operationID: Unique identifier for this operation (for tracking)
    ///   - configuration: Retry configuration to use
    ///   - operation: The async operation to perform
    /// - Returns: The result of the operation
    /// - Throws: The last error encountered if all retries fail
    func withRetry<T>(
        operationID: String,
        configuration: RetryConfiguration = .default,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        AppLog.info("Starting operation with retry: \(operationID)", category: .network)
        
        var lastError: Error?
        var attempt = 0
        
        while attempt < configuration.maxAttempts {
            attempt += 1
            
            do {
                AppLog.debug("Attempt \(attempt)/\(configuration.maxAttempts) for: \(operationID)", category: .network)
                let result = try await operation()
                
                // Success! Log and return
                if attempt > 1 {
                    AppLog.info("✓ Operation succeeded on attempt \(attempt): \(operationID)", category: .network)
                }
                
                // Record successful attempt
                recordAttempt(operationID: operationID)
                
                return result
                
            } catch {
                lastError = error
                AppLog.warning("✗ Attempt \(attempt) failed for \(operationID): \(error)", category: .network)
                
                // Record failed attempt
                recordAttempt(operationID: operationID)
                
                // Classify the error
                let classification = classifyError(error)
                
                // Check if we should retry
                guard classification.shouldRetry else {
                    AppLog.error("Terminal error - not retrying: \(error)", category: .network)
                    throw error
                }
                
                // Check if we have more attempts
                guard attempt < configuration.maxAttempts else {
                    AppLog.error("Max attempts (\(configuration.maxAttempts)) reached for: \(operationID)", category: .network)
                    break
                }
                
                // Calculate delay
                let delay = calculateDelay(
                    attempt: attempt,
                    classification: classification,
                    configuration: configuration
                )
                
                AppLog.info("Retrying after \(String(format: "%.1f", delay))s delay...", category: .network)
                
                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        if let error = lastError {
            AppLog.error("All retries exhausted for: \(operationID). Final error: \(error)", category: .network)
            throw error
        } else {
            AppLog.error("All retries exhausted for: \(operationID). No error recorded.", category: .network)
            throw ExtractionRetryError.allRetriesFailed
        }
    }
    
    /// Get retry statistics for an operation
    func getRetryStats(operationID: String) -> RetryStats {
        let attempts = retryHistory[operationID] ?? []
        return RetryStats(
            totalAttempts: attempts.count,
            lastAttempt: attempts.last,
            attemptHistory: attempts
        )
    }
    
    /// Clear retry history for an operation
    func clearHistory(operationID: String) {
        retryHistory.removeValue(forKey: operationID)
    }
    
    // MARK: - Private Helpers
    
    /// Classify an error to determine if it's retryable
    private func classifyError(_ error: Error) -> ErrorClassification {
        // Handle URLError cases (network errors)
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }
        
        // Handle WebExtractionError
        if let webError = error as? WebExtractionError {
            return classifyWebError(webError)
        }
        
        // Handle ClaudeAPIError
        if let apiError = error as? ClaudeAPIError {
            return classifyAPIError(apiError)
        }
        
        // Handle NSError (generic)
        // All Swift errors can be bridged to NSError, so this is our fallback
        let nsError = error as NSError
        return classifyNSError(nsError)
    }
    
    /// Classify URLError (network errors)
    private func classifyURLError(_ error: URLError) -> ErrorClassification {
        switch error.code {
        // Network connectivity issues - retryable
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return .retryable
            
        // Timeout - retryable
        case .timedOut:
            return .retryable
            
        // Server issues - retryable
        case .badServerResponse,
             .cannotLoadFromNetwork:
            return .retryable
            
        // Authentication/authorization - terminal (wrong credentials)
        case .userAuthenticationRequired,
             .noPermissionsToReadFile:
            return .terminal
            
        // Bad URL - terminal
        case .badURL,
             .unsupportedURL:
            return .terminal
            
        // Certificate issues - terminal (configuration problem)
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot:
            return .terminal
            
        // App Transport Security - terminal (configuration issue)
        case .appTransportSecurityRequiresSecureConnection:
            return .terminal
            
        // Data corruption - terminal
        case .dataNotAllowed,
             .cannotDecodeRawData,
             .cannotDecodeContentData,
             .cannotParseResponse:
            return .terminal
            
        // Resource not available - terminal
        case .resourceUnavailable,
             .fileDoesNotExist:
            return .terminal
            
        default:
            // Unknown URLError - allow retry
            return .retryable
        }
    }
    
    /// Classify WebExtractionError
    private func classifyWebError(_ error: WebExtractionError) -> ErrorClassification {
        switch error {
        case .invalidURL:
            // Bad URL - terminal
            return .terminal
            
        case .networkError:
            // Generic network error - retryable
            return .retryable
            
        case .httpError(let statusCode):
            return classifyHTTPStatusCode(statusCode)
            
        case .decodingError:
            // Data couldn't be decoded - could be transient corruption
            return .retryable
            
        case .noRecipeFound:
            // Page loaded but no recipe found - terminal
            return .terminal
        }
    }
    
    /// Classify ClaudeAPIError
    private func classifyAPIError(_ error: ClaudeAPIError) -> ErrorClassification {
        switch error {
        case .invalidResponse:
            // Invalid response - could be transient
            return .retryable
            
        case .apiError(let statusCode, _):
            return classifyHTTPStatusCode(statusCode)
            
        case .noRecipeFound:
            // No recipe in response - terminal
            return .terminal
            
        case .invalidJSON:
            // JSON parsing failed - could be transient
            return .retryable
            
        case .networkError:
            // Network error - retryable
            return .retryable
            
        case .timeout:
            // Request timed out - retryable (might succeed with more time)
            return .retryable
            
        case .notARecipe:
            // Image doesn't contain a recipe - terminal (won't improve with retry)
            return .terminal
        }
    }
    
    /// Classify generic NSError
    private func classifyNSError(_ error: NSError) -> ErrorClassification {
        let domain = error.domain
        let code = error.code
        
        // Network-related domains
        if domain == NSURLErrorDomain {
            // This should be caught by URLError handler above, but just in case
            return .retryable
        }
        
        // POSIX errors (low-level network/IO)
        if domain == NSPOSIXErrorDomain {
            switch code {
            case 54: // ECONNRESET - Connection reset by peer
                return .retryable
            case 61: // ECONNREFUSED - Connection refused
                return .retryable
            case 64: // EHOSTDOWN - Host is down
                return .retryable
            case 65: // EHOSTUNREACH - No route to host
                return .retryable
            default:
                return .retryable
            }
        }
        
        // Default to retryable for unknown errors
        return .retryable
    }
    
    /// Classify HTTP status codes
    private func classifyHTTPStatusCode(_ statusCode: Int) -> ErrorClassification {
        switch statusCode {
        // Success - shouldn't happen here
        case 200...299:
            return .terminal
            
        // Client errors - mostly terminal
        case 400: // Bad Request
            return .terminal
        case 401: // Unauthorized - could be transient auth issue
            return .retryable
        case 403: // Forbidden - terminal
            return .terminal
        case 404: // Not Found - terminal
            return .terminal
        case 408: // Request Timeout - retryable
            return .retryable
        case 429: // Too Many Requests - retry after delay
            return .retryableAfterDelay(10.0) // Wait 10 seconds
            
        // Server errors - retryable
        case 500...599:
            return .retryable
            
        default:
            return .retryable
        }
    }
    
    /// Calculate delay before next retry
    private func calculateDelay(
        attempt: Int,
        classification: ErrorClassification,
        configuration: RetryConfiguration
    ) -> TimeInterval {
        // If error specifies a delay, use that
        if case .retryableAfterDelay(let delay) = classification {
            return min(delay, configuration.maxDelay)
        }
        
        // Exponential backoff
        let exponentialDelay = configuration.initialDelay * pow(configuration.backoffMultiplier, Double(attempt - 1))
        
        // Cap at max delay
        var delay = min(exponentialDelay, configuration.maxDelay)
        
        // Add jitter to avoid thundering herd
        if configuration.useJitter {
            let jitterRange = delay * 0.3 // ±30% jitter
            let jitter = Double.random(in: -jitterRange...jitterRange)
            delay += jitter
        }
        
        return max(0, delay)
    }
    
    /// Record an attempt for statistics
    private func recordAttempt(operationID: String) {
        if retryHistory[operationID] == nil {
            retryHistory[operationID] = []
        }
        retryHistory[operationID]?.append(Date())
    }
}

// MARK: - Supporting Types

/// Statistics about retry attempts
struct RetryStats: Sendable {
    let totalAttempts: Int
    let lastAttempt: Date?
    let attemptHistory: [Date]
    
    var averageTimeBetweenAttempts: TimeInterval? {
        guard attemptHistory.count >= 2 else { return nil }
        
        var totalTime: TimeInterval = 0
        for i in 1..<attemptHistory.count {
            totalTime += attemptHistory[i].timeIntervalSince(attemptHistory[i-1])
        }
        
        return totalTime / Double(attemptHistory.count - 1)
    }
}

/// Errors specific to the retry manager
enum ExtractionRetryError: LocalizedError {
    case allRetriesFailed
    case operationCancelled
    
    var errorDescription: String? {
        switch self {
        case .allRetriesFailed:
            return "All retry attempts failed"
        case .operationCancelled:
            return "Operation was cancelled"
        }
    }
}
