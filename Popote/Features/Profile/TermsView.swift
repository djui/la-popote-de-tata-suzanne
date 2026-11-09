import SwiftUI

/// The CGU markdown (`terms:fullText`), split the way the website does: on `\n### `.
struct TermsDocument: Equatable {
    enum Block: Equatable {
        case paragraph(String)
        case bullets([String])
    }

    struct Article: Equatable, Identifiable {
        var index: Int
        var title: String
        var blocks: [Block]
        var id: Int { index }
    }

    var title: String
    var subtitle: String
    var version: String
    var articles: [Article]

    static func parse(_ markdown: String) -> TermsDocument {
        let parts = markdown.components(separatedBy: "\n### ")
        let head = parts.first ?? ""
        var title = "", subtitle = "", version = ""
        for line in head.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if line.hasPrefix("## ") { subtitle = String(line.dropFirst(3)) }
            else if line.hasPrefix("# ") { title = String(line.dropFirst(2)) }
            else if version.isEmpty { version = line }
        }
        let articles = parts.dropFirst().enumerated().map { offset, chunk -> Article in
            var lines = chunk.components(separatedBy: "\n")
            let heading = lines.isEmpty ? "" : lines.removeFirst()
            let body = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n- ", with: "\n\n- ")
            let blocks = body.components(separatedBy: "\n\n").compactMap { raw -> Block? in
                let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty else { return nil }
                return p.hasPrefix("- ") ? .bullets([String(p.dropFirst(2))]) : .paragraph(p)
            }
            // Merge consecutive bullets into one list.
            var merged: [Block] = []
            for block in blocks {
                if case .bullets(let new) = block, case .bullets(let old)? = merged.last {
                    merged[merged.count - 1] = .bullets(old + new)
                } else {
                    merged.append(block)
                }
            }
            return Article(index: offset + 1, title: heading.trimmingCharacters(in: .whitespaces), blocks: merged)
        }
        return TermsDocument(title: title, subtitle: subtitle, version: version, articles: articles)
    }

    /// Turns the `[[CONTACT]]` placeholder into a mailto link.
    static func attributed(_ text: String) -> AttributedString {
        let label = LegalTexts.sendEmail.current
        let md = text.replacingOccurrences(of: "[[CONTACT]]", with: "[\(label)](\(LegalTexts.termsMailto.absoluteString))")
        return (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct TermsView: View {
    private let language = AppLanguage.current
    private var document: TermsDocument {
        TermsDocument.parse(language == .en ? LegalTexts.termsEN : LegalTexts.termsFR)
    }

    var body: some View {
        let doc = document
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if language == .en {
                        Text(LegalTexts.termsPrecedenceEN)
                            .font(AppFont.body(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.muted)
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) { Rectangle().fill(Palette.primary).frame(width: 2) }
                            .padding(.bottom, 24)
                    }
                    Text(doc.title)
                        .font(AppFont.display(30, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "La Popote de Tata Suzanne")
                        .font(AppFont.script(30))
                        .foregroundStyle(Palette.primary)
                        .padding(.top, 6)
                    Text(doc.version)
                        .font(AppFont.body(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 12)

                    tableOfContents(doc, proxy: proxy)

                    ForEach(doc.articles) { article in
                        articleView(article)
                            .id(article.index)
                    }

                    Divider().overlay(Palette.line).padding(.top, 8)
                    Link(LegalTexts.sendEmail.current, destination: LegalTexts.termsMailto)
                        .font(AppFont.body(15, weight: .bold))
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .popoteBackground()
        .navigationTitle(language == .en ? "Terms" : "Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, language.locale)
    }

    private func tableOfContents(_ doc: TermsDocument, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language == .en ? "Contents" : "Sommaire")
                .font(AppFont.display(20, bold: false, relativeTo: .title3))
            ForEach(doc.articles) { article in
                Button {
                    withAnimation { proxy.scrollTo(article.index, anchor: .top) }
                } label: {
                    Text(article.title)
                        .font(AppFont.body(15, relativeTo: .subheadline))
                        .underline()
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
        .padding(.vertical, 28)
    }

    private func articleView(_ article: TermsDocument.Article) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(article.title)
                .font(AppFont.display(21, bold: false, relativeTo: .title2))
                .foregroundStyle(Palette.foreground)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(TermsDocument.attributed(text))
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: "•").foregroundStyle(Palette.muted)
                                Text(TermsDocument.attributed(item))
                            }
                        }
                    }
                }
            }
        }
        .font(AppFont.body(16))
        .foregroundStyle(Palette.foreground)
        .lineSpacing(4)
        .tint(Palette.primary)
        .padding(.bottom, 34)
    }
}
