import Foundation
import UIKit
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
//  AttachmentService.swift
//  Xử lý file đính kèm: compress → base64, build API payload cho từng provider
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Attachment model

struct ChatAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let mimeType: String   // "image/jpeg" | "image/png" | "application/pdf"
    let base64: String     // full base64 string (no data: prefix)
    let fileName: String

    init(id: UUID = UUID(), mimeType: String, base64: String, fileName: String = "") {
        self.id = id; self.mimeType = mimeType; self.base64 = base64; self.fileName = fileName
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isPDF:   Bool { mimeType == "application/pdf" }

    /// Thumbnail để hiện trong UI (chỉ cho ảnh)
    var thumbnail: UIImage? {
        guard isImage, let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Compress + encode

enum AttachmentService {

    /// Compress UIImage → JPEG base64. maxShortSide giới hạn kích thước dài nhất.
    static func encode(image: UIImage, maxShortSide: CGFloat = 1568) throws -> ChatAttachment {
        let resized = resize(image, maxShortSide: maxShortSide)
        guard let data = resized.jpegData(compressionQuality: 0.82) else {
            throw EncodingError.cannotCompress
        }
        return ChatAttachment(mimeType: "image/jpeg", base64: data.base64EncodedString(), fileName: "image.jpg")
    }

    /// Encode PDF data → base64 (không resize)
    static func encode(pdfData: Data, fileName: String) -> ChatAttachment {
        ChatAttachment(mimeType: "application/pdf", base64: pdfData.base64EncodedString(), fileName: fileName)
    }

    private static func resize(_ image: UIImage, maxShortSide: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let shorter = min(w, h)
        if shorter <= maxShortSide { return image }
        let scale  = maxShortSide / shorter
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    enum EncodingError: LocalizedError {
        case cannotCompress
        var errorDescription: String? { "Không thể nén ảnh." }
    }

    // MARK: - Build API content per provider

    /// OpenAI / Grok / DeepSeek / Groq — OpenAI-compatible: content = array of parts
    static func openAIContent(text: String, attachments: [ChatAttachment]) -> Any {
        var parts: [[String: Any]] = []
        for att in attachments where att.isImage {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(att.mimeType);base64,\(att.base64)", "detail": "auto"]
            ])
        }
        // PDF: OpenAI gpt-4o hỗ trợ dưới dạng "file" part (beta). Các model cũ không hỗ trợ — bỏ qua.
        parts.append(["type": "text", "text": text])
        return parts.count == 1 ? text : parts   // nếu chỉ có text thì trả string cho model cũ
    }

    /// Anthropic — content = array of content blocks
    static func anthropicContent(text: String, attachments: [ChatAttachment]) -> Any {
        guard !attachments.isEmpty else { return text }
        var blocks: [[String: Any]] = []
        for att in attachments {
            if att.isImage {
                blocks.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": att.mimeType, "data": att.base64]
                ])
            } else if att.isPDF {
                blocks.append([
                    "type": "document",
                    "source": ["type": "base64", "media_type": "application/pdf", "data": att.base64]
                ])
            }
        }
        blocks.append(["type": "text", "text": text])
        return blocks
    }

    /// Gemini — parts = array (text + inlineData)
    static func geminiParts(text: String, attachments: [ChatAttachment]) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        for att in attachments {
            // Gemini hỗ trợ ảnh và PDF qua inlineData
            parts.append(["inlineData": ["mimeType": att.mimeType, "data": att.base64]])
        }
        parts.append(["text": text])
        return parts
    }

    /// Providers không hỗ trợ file (Groq Llama, DeepSeek)
    static func supportsAttachments(_ provider: AIProviderKind) -> Bool {
        switch provider {
        case .openAI, .anthropic, .gemini, .grok: return true
        case .deepseek, .groq: return false
        }
    }

    /// Max số file đính kèm mỗi tin (theo giới hạn API)
    static func maxAttachments(_ provider: AIProviderKind) -> Int {
        switch provider {
        case .anthropic: return 5
        case .gemini:    return 5
        case .openAI:    return 10
        case .grok:      return 4
        default:         return 0
        }
    }
}
