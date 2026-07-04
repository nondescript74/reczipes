//
//  SafariView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/29/26.
//


// MARK: - SafariView Wrapper

import SwiftUI
#if os(iOS)
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let entersReaderIfAvailable: Bool

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = entersReaderIfAvailable
        configuration.barCollapsingEnabled = true

        let safariVC = SFSafariViewController(url: url, configuration: configuration)
        safariVC.dismissButtonStyle = .done

        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}
#else
import WebKit

/// macOS fallback: an in-app browser backed by WKWebView. Keeps the same
/// initializer signature as the iOS `SFSafariViewController` wrapper.
struct SafariView: NSViewRepresentable {
    let url: URL
    let entersReaderIfAvailable: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
#endif

// Alternative: Use the standard SwiftUI approach
extension View {
    func safariView(url: Binding<URL?>, isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            if let url = url.wrappedValue {
                SafariView(url: url, entersReaderIfAvailable: true)
                    .ignoresSafeArea()
            }
        }
    }
}
