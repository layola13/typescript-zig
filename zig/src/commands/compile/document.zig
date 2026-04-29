const std = @import("std");

/// Document highlight kind
pub const HighlightKind = enum {
    none,
    definition,
    reference,
    read,
    write,
};

/// Document highlight
pub const DocumentHighlight = struct {
    file_name: []const u8,
    span: Span,
    kind: HighlightKind,
};

/// Span
pub const Span = struct {
    start: u32,
    length: u32,
};

/// Outlining spans
pub const OutliningSpan = struct {
    span: Span,
    text_span: Span,
    banner_text: []const u8,
    auto_collapse: bool = false,
    kind: OutliningSpanKind,
};

/// Outlining span kind
pub const OutliningSpanKind = enum {
    /// Comment
    comment,
    /// Block comment
    block,
    /// Doc comment
    doc_comment,
    /// Region
    region,
    /// Code
    code,
    /// Import or export
    import_or_export,
};

/// Brace matching result
pub const BraceMatchingResult = struct {
    file_name: []const u8,
    spans: []Span,
};

/// Indentation result
pub const IndentationResult = struct {
    position: u32,
    indentation: u32,
};

/// Doc comment template
pub const DocCommentTemplate = struct {
    tag: []const u8,
    min_width: i32,
    indentation: u32,
};

/// todo comment
pub const TodoComment = struct {
    token: []const u8,
    position: u32,
    priority: u32,
};
