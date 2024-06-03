const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const log = std.log.scoped(.spirv_tools);

// ----------------------
// Python execution logic
// ----------------------

fn ensureCommandExists(allocator: std.mem.Allocator, name: []const u8, exist_check: []const u8) bool {
    const result = std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ name, exist_check },
        .cwd = ".",
    }) catch // e.g. FileNotFound
        {
        return false;
    };

    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    if (result.term.Exited != 0)
        return false;

    return true;
}


fn exec(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    for (argv) |arg| {
        try std.fmt.format(buf.writer(), "{s} ", .{arg});
    }

    var child = std.ChildProcess.init(argv, allocator);
    child.cwd = cwd;
    _ = try child.spawnAndWait();
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn runPython(allocator: std.mem.Allocator, args: []const []const u8, errMsg: []const u8) void {
    exec(allocator, args, sdkPath("/")) catch |err|
    {
        log.err("{s}. error: {s}", .{ errMsg, @errorName(err) });
        std.process.exit(1);
    };
}

// -------------------------------
// SPIR-V include generation logic
// -------------------------------

pub const spirv_output_path = "generated-include";

const grammar_tables_script = "utils/generate_grammar_tables.py";
const language_headers_script = "utils/generate_language_headers.py";
const build_version_script = "utils/update_build_version.py";
const gen_registry_tables_script = "utils/generate_registry_tables.py";

const debuginfo_insts_file = "/include/spirv/unified1/extinst.debuginfo.grammar.json";
const cldebuginfo100_insts_file = "/include/spirv/unified1/extinst.opencl.debuginfo.100.grammar.json";


fn spvHeaderFile(comptime version: []const u8, comptime file_name: []const u8, comptime header_path: []const u8) []const u8 {
    return (header_path ++ "/include/spirv/" ++ version ++ "/" ++ file_name);
}

// Script usage derived from BUILD.gn

fn genSPIRVCoreTables(allocator: std.mem.Allocator, comptime version: []const u8, comptime header_path: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json", header_path);

    // Outputs
    const core_insts_file = spirv_output_path ++ "/core.insts-" ++ version ++ ".inc";
    const operand_kinds_file = spirv_output_path ++ "/operand.kinds-" ++ version ++ ".inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--core-insts-output", core_insts_file, 
        "--extinst-debuginfo-grammar", (header_path ++ debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", (header_path ++ cldebuginfo100_insts_file), 
        "--operand-kinds-output", operand_kinds_file, 
        "--output-language", "c++" 
    };

    runPython(allocator, args, "Failed to build SPIR-V core tables");
}

fn genSPIRVCoreEnums(allocator: std.mem.Allocator, comptime version: []const u8, comptime header_path: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json", header_path);

    const extension_enum_file = spirv_output_path ++ "/extension_enum.inc";
    const extension_map_file = spirv_output_path ++ "/enum_string_mapping.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", (header_path ++ debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", (header_path ++ cldebuginfo100_insts_file), 
        "--extension-enum-output", extension_enum_file, 
        "--enum-string-mapping-output", extension_map_file, 
        "--output-language", "c++"
    };

    runPython(allocator, args, "Failed to build SPIR-V core enums");
}

fn genSPIRVGlslTables(allocator: std.mem.Allocator, comptime version: []const u8, comptime header_path: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json", header_path);
    const glsl_json_file = spvHeaderFile(version, "extinst.glsl.std.450.grammar.json", header_path);

    const glsl_insts_file = spirv_output_path ++ "/glsl.std.450.insts.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", (header_path ++ debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", (header_path ++ cldebuginfo100_insts_file), 
        "--extinst-glsl-grammar", glsl_json_file, 
        "--glsl-insts-output", glsl_insts_file, 
        "--output-language", "c++" 
    };

    runPython(allocator, args, "Failed to build SPIR-V GLSL tables");
}

fn genSPIRVOpenCLTables(allocator: std.mem.Allocator, comptime version: []const u8, comptime header_path: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json", header_path);
    const opencl_json_file = spvHeaderFile(version, "extinst.opencl.std.100.grammar.json", header_path);

    const opencl_insts_file = spirv_output_path ++ "/opencl.std.insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--spirv-core-grammar", core_json_file,
        "--extinst-debuginfo-grammar", (header_path ++ debuginfo_insts_file),
        "--extinst-cldebuginfo100-grammar", (header_path ++ cldebuginfo100_insts_file),
        "--extinst-opencl-grammar", opencl_json_file,
        "--opencl-insts-output", opencl_insts_file,
    };

    runPython(allocator, args, "Failed to build SPIR-V OpenCL tables");
}

fn genSPIRVLanguageHeader(allocator: std.mem.Allocator, comptime name: []const u8, comptime grammar_file: []const u8) void {
    const extinst_output_path = spirv_output_path ++ "/" ++ name ++ ".h";

    const args = &[_][]const u8{
        "python3", language_headers_script,
        "--extinst-grammar", grammar_file,
        "--extinst-output-path", extinst_output_path,
    };

    runPython(allocator, args, "Failed to generate SPIR-V language header '" ++ name);
}

fn genSPIRVVendorTable(allocator: std.mem.Allocator, comptime name: []const u8, comptime operand_kind_tools_prefix: []const u8, comptime header_path: []const u8) void {
    const extinst_vendor_grammar = (header_path ++ "/include/spirv/unified1/extinst." ++ name ++ ".grammar.json");
    const extinst_file = spirv_output_path ++ "/" ++ name ++ ".insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--extinst-vendor-grammar", extinst_vendor_grammar,
        "--vendor-insts-output", extinst_file,
        "--vendor-operand-kind-prefix", operand_kind_tools_prefix,
    };

    runPython(allocator, args, "Failed to generate SPIR-V vendor table '" ++ name);
}

fn genSPIRVRegistryTables(allocator: std.mem.Allocator, comptime header_path: []const u8) void {
    const xml_file = (header_path ++ "/include/spirv/spir-v.xml");
    const inc_file = spirv_output_path ++ "/generators.inc";

    const args = &[_][]const u8{
        "python3", gen_registry_tables_script,
        "--xml", xml_file,
        "--generator", inc_file,
    };

    runPython(allocator, args, "Failed to generate SPIR-V registry tables");
}

fn buildSPIRVVersion(allocator: std.mem.Allocator, comptime header_path: []const u8) void {
    const changes_file = "./CHANGES";
    const inc_file = spirv_output_path ++ "/build-version.inc";

    _ = header_path;

    const args = &[_][]const u8{
        "python3", build_version_script,
        changes_file,
        inc_file,
    };

    runPython(allocator, args, "Failed to generate SPIR-V build version");
}

pub fn generateSPIRVHeaders(allocator: std.mem.Allocator, comptime header_path: []const u8) void {
    _ = std.fs.openDirAbsolute(sdkPath("/" ++ header_path), .{}) catch |err| {
        if (err == error.FileNotFound) {
            log.err("SPIRV-Headers was not found - please provide a valid path to a SPIRV-Headers directory.", .{});
        }

        std.process.exit(1);
    };

    if (!ensureCommandExists(allocator, "python3", "--version")) {
        log.err("'python3 --version' failed. Is python not installed?", .{});
        std.process.exit(1);
    }

    genSPIRVCoreTables(allocator, "unified1", header_path);
    genSPIRVCoreEnums(allocator, "unified1", header_path);

    genSPIRVGlslTables(allocator, "1.0", header_path);

    genSPIRVOpenCLTables(allocator, "1.0", header_path);

    genSPIRVLanguageHeader(allocator, "DebugInfo", spvHeaderFile("unified1", "extinst.debuginfo.grammar.json", header_path));
    genSPIRVLanguageHeader(allocator, "OpenCLDebugInfo100", spvHeaderFile("unified1", "extinst.opencl.debuginfo.100.grammar.json", header_path));
    genSPIRVLanguageHeader(allocator, "NonSemanticShaderDebugInfo100", spvHeaderFile("unified1", "extinst.nonsemantic.shader.debuginfo.100.grammar.json", header_path));

    genSPIRVVendorTable(allocator, "spv-amd-shader-explicit-vertex-parameter", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "spv-amd-shader-trinary-minmax", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "spv-amd-gcn-shader", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "spv-amd-shader-ballot", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "debuginfo", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "opencl.debuginfo.100", "CLDEBUG100_", header_path);
    genSPIRVVendorTable(allocator, "nonsemantic.clspvreflection", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "nonsemantic.vkspreflection", "...nil...", header_path);
    genSPIRVVendorTable(allocator, "nonsemantic.shader.debuginfo.100", "SHDEBUG100_", header_path);

    genSPIRVRegistryTables(allocator, header_path);

    buildSPIRVVersion(allocator, header_path);
}