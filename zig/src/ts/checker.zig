//! Type checker for TypeScript
//! Implements type inference and validation

const std = @import("std");
const ast = @import("./ast.zig");
const types = @import("./types.zig");
const symbol = @import("./sema/symbol_table.zig");
const diagnostics = @import("../diagnostics/diagnostic.zig");

/// Type checker context
pub const Checker = struct {
    allocator: std.mem.Allocator,
    program: *const ast.Program,
    symbols: *symbol.SymbolTable,
    errors: std.ArrayList(diagnostics.Diagnostic),
    current_file: ?[:0]const u8 = null,
    current_line: u32 = 0,
    current_column: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, program: *const ast.Program, symbols: *symbol.SymbolTable) Checker {
        return .{
            .allocator = allocator,
            .program = program,
            .symbols = symbols,
            .errors = std.ArrayList(diagnostics.Diagnostic).init(allocator),
        };
    }

    pub fn checkProgram(self: *Checker) !CheckResult {
        var summary = CheckSummary{};
        for (self.program.source_files.items) |source_file| {
            self.current_file = source_file.file_name;
            try self.checkSourceFile(source_file, &summary);
        }
        return CheckResult{
            .success = self.errors.items.len == 0,
            .error_count = self.errors.items.len,
            .summary = summary,
        };
    }

    fn checkSourceFile(self: *Checker, source_file: *const ast.SourceFile, summary: *CheckSummary) !void {
        for (source_file.statements.items) |stmt| {
            try self.checkStatement(stmt, summary);
        }
    }

    fn checkStatement(self: *Checker, stmt: *const ast.Statement, summary: *CheckSummary) !void {
        switch (stmt.kind) {
            .variable_statement => |var_stmt| try self.checkVariableDeclaration(var_stmt, summary),
            .function_declaration => |func| try self.checkFunctionDeclaration(func, summary),
            .class_declaration => |class| try self.checkClassDeclaration(class, summary),
            .expression_statement => |expr| _ = try self.checkExpression(expr),
            .if_statement => |if_stmt| try self.checkIfStatement(if_stmt, summary),
            .for_statement => |for_stmt| try self.checkForStatement(for_stmt, summary),
            .return_statement => |ret| {
                if (ret.expression) |expr| _ = try self.checkExpression(expr);
            },
            else => {},
        }
    }

    fn checkVariableDeclaration(self: *Checker, var_stmt: *const ast.VariableStatement, summary: *CheckSummary) !void {
        summary.variable_count += 1;
        for (var_stmt.declaration_list.declarations.items) |decl| {
            const name = decl.name;
            if (decl.initializer) |init| {
                const inferred = try self.checkExpression(init);
                if (decl.type_node) |type_node| {
                    const declared = try self.getTypeFromTypeNode(type_node);
                    if (!types.isAssignableTo(inferred, declared)) {
                        try self.addError("TS2322", "Type is not assignable to type", name.start.pos);
                    }
                }
            }
        }
    }

    fn checkFunctionDeclaration(self: *Checker, func: *const ast.FunctionDeclaration, summary: *CheckSummary) !void {
        summary.function_count += 1;
        if (func.return_type_node) |ret_type| _ = try self.getTypeFromTypeNode(ret_type);
        if (func.body) |body| {
            for (body.statements.items) |stmt| try self.checkStatement(stmt, summary);
        }
    }

    fn checkClassDeclaration(self: *Checker, class: *const ast.ClassDeclaration, summary: *CheckSummary) !void {
        summary.class_count += 1;
        for (class.members.items) |member| {
            switch (member) {
                .method => |method| try self.checkFunctionDeclaration(method, summary),
                .property => |prop| {
                    if (prop.type_node) |tn| _ = try self.getTypeFromTypeNode(tn);
                    if (prop.initializer) |init| _ = try self.checkExpression(init);
                },
                else => {},
            }
        }
    }

    fn checkIfStatement(self: *Checker, if_stmt: *const ast.IfStatement, summary: *CheckSummary) !void {
        _ = try self.checkExpression(if_stmt.expression);
        if (if_stmt.then_statement) |then_| try self.checkStatement(then_, summary);
        if (if_stmt.else_statement) |else_| try self.checkStatement(else_, summary);
    }

    fn checkForStatement(self: *Checker, for_stmt: *const ast.ForStatement, summary: *CheckSummary) !void {
        if (for_stmt.initializer) |init| try self.checkStatement(init, summary);
        if (for_stmt.condition) |cond| _ = try self.checkExpression(cond);
        if (for_stmt.incrementor) |inc| _ = try self.checkExpression(inc);
        if (for_stmt.body) |body| try self.checkStatement(body, summary);
    }

    fn checkExpression(self: *Checker, expr: *const ast.Expression) !types.Type {
        switch (expr.kind) {
            .numeric_literal => return types.Type{ .primitive = .number },
            .string_literal => return types.Type{ .primitive = .string },
            .boolean_literal => return types.Type{ .primitive = .boolean },
            .null_keyword => return types.Type{ .primitive = .null },
            .undefined_keyword => return types.Type{ .primitive = .undefined },
            .identifier => return try self.getIdentifierType(expr.identifier),
            .array_literal => return types.Type{ .object = .array },
            .object_literal => return types.Type{ .object = .object },
            .binary_expression => return try self.checkBinaryExpression(expr),
            .unary_expression => return try self.checkUnaryExpression(expr),
            .call_expression => return types.Type{ .primitive = .unknown },
            .property_access_expression => return types.Type{ .primitive = .unknown },
            .element_access_expression => return types.Type{ .primitive = .unknown },
            .template_expression => return types.Type{ .primitive = .string },
            .function_expression => return types.Type{ .object = .function },
            .arrow_function => return types.Type{ .object = .function },
            .parenthesized => return try self.checkExpression(expr.expression),
            .as_expression => return try self.getTypeFromTypeNode(expr.as_type_node.?),
            .type_of_expression => return types.Type{ .primitive = .string },
            .assignment_expression => return try self.checkAssignmentExpression(expr),
            else => return types.Type{ .primitive = .unknown },
        }
    }

    fn getIdentifierType(self: *Checker, ident: ast.Identifier) !types.Type {
        if (self.symbols.lookup(ident.escaped_text)) |sym| {
            if (sym.type_info.len > 0) {
                return self.parseTypeFromString(sym.type_info);
            }
        }
        return types.Type{ .primitive = .unknown };
    }

    fn parseTypeFromString(self: *Checker, type_str: []const u8) types.Type {
        _ = self;
        if (std.mem.eql(u8, type_str, "number")) return types.Type{ .primitive = .number };
        if (std.mem.eql(u8, type_str, "string")) return types.Type{ .primitive = .string };
        if (std.mem.eql(u8, type_str, "boolean")) return types.Type{ .primitive = .boolean };
        if (std.mem.eql(u8, type_str, "any")) return types.Type{ .primitive = .any };
        if (std.mem.eql(u8, type_str, "void")) return types.Type{ .primitive = .void };
        if (std.mem.eql(u8, type_str, "null")) return types.Type{ .primitive = .null };
        if (std.mem.eql(u8, type_str, "undefined")) return types.Type{ .primitive = .undefined };
        if (std.mem.eql(u8, type_str, "unknown")) return types.Type{ .primitive = .unknown };
        if (std.mem.eql(u8, type_str, "never")) return types.Type{ .primitive = .never };
        return types.Type{ .primitive = .unknown };
    }

    fn checkBinaryExpression(self: *Checker, expr: *const ast.Expression) !types.Type {
        const left = try self.checkExpression(expr.binary_left.?);
        const right = try self.checkExpression(expr.binary_right.?);
        switch (expr.binary_operator) {
            // Arithmetic operators - return number (or string for +)
            .plus, .minus, .asterisk, .slash, .percent,
            .asterisk_asterisk, .less_than_less_than,
            .greater_than_greater_than, .greater_than_greater_than_greater_than => {
                // String concatenation with + operator
                if (expr.binary_operator == .plus) {
                    if (left == .primitive and left.primitive == .string) return types.Type{ .primitive = .string };
                    if (right == .primitive and right.primitive == .string) return types.Type{ .primitive = .string };
                }
                return types.Type{ .primitive = .number };
            },
            // Comparison operators - return boolean
            .less_than, .greater_than, .less_than_equals,
            .greater_than_equals => {
                return types.Type{ .primitive = .boolean };
            },
            // Equality operators - return boolean
            .equals_equals, .exclamation_equals,
            .equals_equals_equals, .exclamation_equals_equals => {
                return types.Type{ .primitive = .boolean };
            },
            // Logical operators
            .ampersand_ampersand, .pipe_pipe => {
                return types.Type{ .primitive = .boolean };
            },
            else => return types.Type{ .primitive = .unknown },
        }
    }

    fn checkUnaryExpression(self: *Checker, expr: *const ast.Expression) !types.Type {
        _ = self;
        switch (expr.prefix_unary_operator) {
            .plus, .minus, .tilde => return types.Type{ .primitive = .number },
            .exclamation => return types.Type{ .primitive = .boolean },
            else => return types.Type{ .primitive = .unknown },
        }
    }

    fn checkAssignmentExpression(self: *Checker, expr: *const ast.Expression) !types.Type {
        const right = try self.checkExpression(expr.binary_right.?);
        _ = expr.binary_left; // Could add LHS type checking here
        return right;
    }

    fn getTypeFromTypeNode(self: *Checker, type_node: *const ast.TypeNode) !types.Type {
        _ = self;
        switch (type_node.kind) {
            .keyword => {
                switch (type_node.keyword) {
                    .void_keyword => return types.Type{ .primitive = .void },
                    .number_keyword => return types.Type{ .primitive = .number },
                    .string_keyword => return types.Type{ .primitive = .string },
                    .boolean_keyword => return types.Type{ .primitive = .boolean },
                    .null_keyword => return types.Type{ .primitive = .null },
                    .undefined_keyword => return types.Type{ .primitive = .undefined },
                    .any_keyword => return types.Type{ .primitive = .any },
                    .unknown_keyword => return types.Type{ .primitive = .unknown },
                    .never_keyword => return types.Type{ .primitive = .never },
                    .object_keyword => return types.Type{ .object = .object },
                    .symbol_keyword => return types.Type{ .primitive = .symbol },
                    .bigint_keyword => return types.Type{ .primitive = .bigint },
                    else => return types.Type{ .primitive = .unknown },
                }
            },
            .literal => return types.Type{ .primitive = .number },
            .array => return types.Type{ .object = .array },
            .type_reference => return types.Type{ .primitive = .unknown },
            .func => return types.Type{ .object = .func },
            .union => return types.Type{ .primitive = .unknown },
            .intersection => return types.Type{ .primitive = .unknown },
            else => return types.Type{ .primitive = .unknown },
        }
    }

    fn addError(self: *Checker, code: []const u8, message: []const u8, pos: u32) !void {
        const diag = diagnostics.Diagnostic{
            .range = .{
                .start = .{ .line = self.current_line, .character = pos },
                .end = .{ .line = self.current_line, .character = pos },
            },
            .severity = diagnostics.DiagnosticSeverity.error,
            .code = code,
            .message = message,
        };
        try self.errors.append(diag);
    }

    pub fn destroy(self: *Checker) void {
        self.errors.deinit();
    }
};

/// Check result
pub const CheckResult = struct {
    success: bool,
    error_count: usize,
    summary: CheckSummary,
};

/// Check summary
pub const CheckSummary = struct {
    variable_count: usize = 0,
    function_count: usize = 0,
    class_count: usize = 0,
    interface_count: usize = 0,
    type_alias_count: usize = 0,
    call_count: usize = 0,
};
/// Check if function type source is assignable to target
fn isFunctionAssignableTo(source: Signature, target: Signature) bool {
    // Return type must be assignable (contravariant for params)
    if (!isAssignableTo(target.return_type, source.return_type)) return false;

    // Parameter count must match (unless target has rest params)
    if (source.params.len < target.params.len) return false;

    // Check each parameter
    const min_len = target.params.len;
    for (target.params, 0..min_len) |tparam, i| {
        if (!isAssignableTo(source.params[i], tparam)) return false;
    }

    return true;
}
// ============================================================================
// AST Node Types
// ============================================================================

/// Source position for error reporting
pub const Position = struct {
    line: u32,
    column: u32,
    offset: u32,
};
/// Source range
pub const Range = struct {
    start: Position,
    end: Position,
};
/// Program node
pub const Program = struct {
    source_files: std.ArrayList(SourceFile),
};
/// Source file node
pub const SourceFile = struct {
    file_name: [:0]const u8,
    statements: std.ArrayList(*const Statement),
};
/// Statement kinds
pub const StatementKind = enum {
    variable_statement,
    function_declaration,
    class_declaration,
    interface_declaration,
    enum_declaration,
    type_alias_declaration,
    module_declaration,
    expression_statement,
    if_statement,
    while_statement,
    do_statement,
    for_statement,
    for_in_statement,
    for_of_statement,
    switch_statement,
    case_clause,
    default_clause,
    break_statement,
    continue_statement,
    return_statement,
    throw_statement,
    try_statement,
    with_statement,
    labeled_statement,
    debugger_statement,
    empty_statement,
};
/// Variable statement
pub const VariableStatement = struct {
    declaration_list: *const VariableDeclarationList,
    pos: u32 = 0,
};
/// Variable declaration
pub const VariableDeclaration = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    initializer: ?*const Expression = null,
    pos: u32 = 0,
};
/// Variable declaration list
pub const VariableDeclarationList = struct {
    declarations: std.ArrayList(*const VariableDeclaration),
    flags: u32 = 0,
};
/// Function declaration
pub const FunctionDeclaration = struct {
    name: []const u8,
    parameters: std.ArrayList(*const ParameterDeclaration),
    return_type_node: ?*const TypeNode = null,
    body: ?*const Block = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    is_async: bool = false,
    is_generator: bool = false,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Parameter declaration
pub const ParameterDeclaration = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    initializer: ?*const Expression = null,
    is_rest: bool = false,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Block
pub const Block = struct {
    statements: std.ArrayList(*const Statement),
    pos: u32 = 0,
};
/// Class declaration
pub const ClassDeclaration = struct {
    name: []const u8,
    members: std.ArrayList(*const ClassMember),
    extends_clause: ?*const HeritageClause = null,
    implements_clause: ?*const HeritageClause = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Class member kinds
pub const ClassMemberKind = enum {
    constructor,
    method,
    property,
    get_accessor,
    set_accessor,
    index_signature,
};
/// Class member
pub const ClassMember = union(ClassMemberKind) {
    constructor: *const ConstructorDeclaration,
    method: *const MethodDeclaration,
    property: *const PropertyDeclaration,
    get_accessor: *const GetAccessorDeclaration,
    set_accessor: *const SetAccessorDeclaration,
    index_signature: *const IndexSignatureDeclaration,
};
/// Constructor declaration
pub const ConstructorDeclaration = struct {
    parameters: std.ArrayList(*const ParameterDeclaration),
    body: ?*const Block = null,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Method declaration
pub const MethodDeclaration = struct {
    name: []const u8,
    parameters: std.ArrayList(*const ParameterDeclaration),
    return_type_node: ?*const TypeNode = null,
    body: ?*const Block = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Property declaration
pub const PropertyDeclaration = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    initializer: ?*const Expression = null,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Get accessor declaration
pub const GetAccessorDeclaration = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    body: ?*const Block = null,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Set accessor declaration
pub const SetAccessorDeclaration = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    parameter: ?*const ParameterDeclaration = null,
    body: ?*const Block = null,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Index signature declaration
pub const IndexSignatureDeclaration = struct {
    key_name: []const u8,
    key_type_node: ?*const TypeNode = null,
    type_node: *const TypeNode,
    readonly: bool = false,
    modifiers: u32 = 0,
    pos: u32 = 0,
};
/// Heritage clause (extends/implements)
pub const HeritageClause = struct {
    types: std.ArrayList(*const ExpressionWithTypeArguments),
    pos: u32 = 0,
};
/// Expression with type arguments
pub const ExpressionWithTypeArguments = struct {
    expression: *const Expression,
    type_args: std.ArrayList(*const TypeNode) = undefined,
    pos: u32 = 0,
};
/// Interface declaration
pub const InterfaceDeclaration = struct {
    name: []const u8,
    members: std.ArrayList(*const InterfaceMember),
    extends_clause: ?*const HeritageClause = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    pos: u32 = 0,
};
/// Interface member kinds
pub const InterfaceMemberKind = enum {
    property_signature,
    method_signature,
    call_signature,
    construct_signature,
    index_signature,
};
/// Interface member
pub const InterfaceMember = union(InterfaceMemberKind) {
    property_signature: *const PropertySignature,
    method_signature: *const MethodSignature,
    call_signature: *const CallSignatureDeclaration,
    construct_signature: *const ConstructSignatureDeclaration,
    index_signature: *const IndexSignatureDeclaration,
};
/// Method signature
pub const MethodSignature = struct {
    name: []const u8,
    parameters: std.ArrayList(*const ParameterDeclaration),
    return_type_node: ?*const TypeNode = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    pos: u32 = 0,
};
/// Property signature
pub const PropertySignature = struct {
    name: []const u8,
    type_node: ?*const TypeNode = null,
    optional: bool = false,
    readonly: bool = false,
    initializer: ?*const Expression = null,
    pos: u32 = 0,
};
/// Call signature declaration
pub const CallSignatureDeclaration = struct {
    parameters: std.ArrayList(*const ParameterDeclaration),
    return_type_node: ?*const TypeNode = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    pos: u32 = 0,
};
/// Construct signature declaration
pub const ConstructSignatureDeclaration = struct {
    parameters: std.ArrayList(*const ParameterDeclaration),
    return_type_node: ?*const TypeNode = null,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    pos: u32 = 0,
};
/// Type alias declaration
pub const TypeAliasDeclaration = struct {
    name: []const u8,
    type_node: *const TypeNode,
    type_params: std.ArrayList(*const TypeParameter) = undefined,
    pos: u32 = 0,
};
/// Enum member
pub const EnumMember = struct {
    name: []const u8,
    initializer: ?*const Expression = null,
    pos: u32 = 0,
};
/// Module declaration
pub const ModuleDeclaration = struct {
    name: []const u8,
    body: ?*const Block = null,
    pos: u32 = 0,
};
/// Enum declaration
pub const EnumDeclaration = struct {
    name: []const u8,
    members: std.ArrayList(*const EnumMember),
    is_const: bool = false,
    is_export: bool = false,
    pos: u32 = 0,
};
/// If statement
pub const IfStatement = struct {
    expression: *const Expression,
    then_statement: *const Statement,
    else_statement: ?*const Statement = null,
    pos: u32 = 0,
};
/// Do statement
pub const DoStatement = struct {
    statement: *const Statement,
    expression: *const Expression,
    pos: u32 = 0,
};
/// While statement
pub const WhileStatement = struct {
    expression: *const Expression,
    statement: *const Statement,
    pos: u32 = 0,
};
/// For statement
pub const ForStatement = struct {
    initializer: ?*const ForLoopInitializer = null,
    condition: ?*const Expression = null,
    incrementor: ?*const Expression = null,
    statement: *const Statement,
    pos: u32 = 0,
};
/// For loop initializer
pub const ForLoopInitializer = struct {
    kind: ForLoopInitializerKind,
};
pub const ForLoopInitializerKind = enum {
    variable, 
    expression,
};
/// ForIn statement
pub const ForInStatement = struct {
    initializer: *const ForLoopInitializer,
    expression: *const Expression,
    statement: *const Statement,
    pos: u32 = 0,
};
/// ForOf statement
pub const ForOfStatement = struct {
    initializer: *const ForLoopInitializer,
    expression: *const Expression,
    statement: *const Statement,
    is_await: bool = false,
    pos: u32 = 0,
};
/// Switch clause
pub const SwitchClause = union(SwitchClauseKind) {
    case_clause: *const CaseClause,
    default_clause: *const DefaultClause,
};
/// Switch statement
pub const SwitchStatement = struct {
    expression: *const Expression,
    clauses: std.ArrayList(*const SwitchClause),
    pos: u32 = 0,
};
/// Case clause
pub const CaseClause = struct {
    expression: *const Expression,
    statements: std.ArrayList(*const Statement),
    pos: u32 = 0,
};
/// Switch clause kinds
pub const SwitchClauseKind = enum {
    case_clause,
    default_clause,
};
/// Break statement
pub const BreakStatement = struct {
    label: ?[]const u8 = null,
    pos: u32 = 0,
};
/// Return statement
pub const ReturnStatement = struct {
    expression: ?*const Expression = null,
    pos: u32 = 0,
};
/// Default clause
pub const DefaultClause = struct {
    statements: std.ArrayList(*const Statement),
    pos: u32 = 0,
};
/// Continue statement
pub const ContinueStatement = struct {
    label: ?[]const u8 = null,
    pos: u32 = 0,
};
/// Throw statement
pub const ThrowStatement = struct {
    expression: *const Expression,
    pos: u32 = 0,
};
/// Try statement
pub const TryStatement = struct {
    try_block: *const Block,
    catch_clause: ?*const CatchClause = null,
    finally_block: ?*const FinallyClause = null,
    pos: u32 = 0,
};
/// Catch clause
pub const CatchClause = struct {
    variable_name: ?[]const u8 = null,
    block: *const Block,
    pos: u32 = 0,
};
/// Finally clause
pub const FinallyClause = struct {
    block: *const Block,
    pos: u32 = 0,
};
/// With statement
pub const WithStatement = struct {
    expression: *const Expression,
    statement: *const Statement,
    pos: u32 = 0,
};
/// Labeled statement
pub const LabeledStatement = struct {
    label: []const u8,
    statement: *const Statement,
    pos: u32 = 0,
};
/// Debugger statement
pub const DebuggerStatement = struct {
    pos: u32 = 0,
};
/// Empty statement
pub const EmptyStatement = struct {
    pos: u32 = 0,
};
/// Statement wrapper
pub const Statement = union(StatementKind) {
    variable_statement: *const VariableStatement,
    function_declaration: *const FunctionDeclaration,
    class_declaration: *const ClassDeclaration,
    interface_declaration: *const InterfaceDeclaration,
    enum_declaration: *const EnumDeclaration,
    type_alias_declaration: *const TypeAliasDeclaration,
    module_declaration: *const ModuleDeclaration,
    expression_statement: *const Expression,
    if_statement: *const IfStatement,
    while_statement: *const WhileStatement,
    do_statement: *const DoStatement,
    for_statement: *const ForStatement,
    for_in_statement: *const ForInStatement,
    for_of_statement: *const ForOfStatement,
    switch_statement: *const SwitchStatement,
    case_clause: *const CaseClause,
    default_clause: *const DefaultClause,
    break_statement: *const BreakStatement,
    continue_statement: *const ContinueStatement,
    return_statement: *const ReturnStatement,
    throw_statement: *const ThrowStatement,
    try_statement: *const TryStatement,
    with_statement: *const WithStatement,
    labeled_statement: *const LabeledStatement,
    debugger_statement: *const DebuggerStatement,
    empty_statement: *const EmptyStatement,
};
