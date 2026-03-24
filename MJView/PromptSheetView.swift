//
//  PromptSheetView.swift
//  MJView
//

import SwiftUI

struct PromptSheetView: View {
    let fileName: String
    let prompt: String?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt")
                        .font(.headline)
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            if let prompt {
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No prompt found")
                        .foregroundStyle(.secondary)
                    Text("This PNG doesn't contain MidJourney XMP metadata.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 200)
    }
}
