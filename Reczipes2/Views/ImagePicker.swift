//
//  ImagePicker.swift
//  Reczipes2
//
//  Created for image selection
//

import SwiftUI
#if os(iOS)
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: ImagePickerSourceType
    let onImageSelected: (PlatformImage) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = (sourceType == .camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Dismiss immediately
            parent.dismiss()

            // Then handle the image after dismiss completes
            if let image = info[.originalImage] as? PlatformImage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.parent.onImageSelected(image)
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.parent.onCancel()
            }
        }
    }
}
#else
import AppKit

/// macOS fallback: presents an `NSOpenPanel` to choose an image file. Keeps the
/// same initializer signature as the iOS `UIImagePickerController` wrapper.
/// (There is no camera-capture equivalent on macOS; both source types open the panel.)
struct ImagePicker: View {
    let sourceType: ImagePickerSourceType
    let onImageSelected: (PlatformImage) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let images = MacFilePicker.pickImages(allowsMultiple: false)
                if let first = images.first {
                    onImageSelected(first)
                } else {
                    onCancel()
                }
                dismiss()
            }
    }
}
#endif
