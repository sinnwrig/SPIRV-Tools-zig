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

const HeaderGenInfo = struct {
    b: *Build,
    header_path: []const u8, 
};

pub const spirv_output_path = "generated-include";

const grammar_tables_script = "utils/generate_grammar_tables.py";
const language_headers_script = "utils/generate_language_headers.py";
const build_version_script = "utils/update_build_version.py";
const gen_registry_tables_script = "utils/generate_registry_tables.py";

const debuginfo_insts_file = "/include/spirv/unified1/extinst.debuginfo.grammar.json";
const cldebuginfo100_insts_file = "/include/spirv/unified1/extinst.opencl.debuginfo.100.grammar.json";


fn headerPath(info: HeaderGenInfo, path: []const u8) []u8 {
    const paths = &[_][]const u8{
        info.header_path, path
    };

    return info.b.pathJoin(paths);
}


fn spvHeaderFile(info: HeaderGenInfo, comptime version: []const u8, comptime file_name: []const u8) []u8 {
    const paths = &[_][]const u8{
        info.header_path, "include", "spirv", version, file_name
    };

    return info.b.pathJoin(paths);
}

// Script usage derived from BUILD.gn

fn genSPIRVCoreTables(info: HeaderGenInfo, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(info, version, "spirv.core.grammar.json");

    // Outputs
    const core_insts_file = spirv_output_path ++ "/core.insts-" ++ version ++ ".inc";
    const operand_kinds_file = spirv_output_path ++ "/operand.kinds-" ++ version ++ ".inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--core-insts-output", core_insts_file, 
        "--extinst-debuginfo-grammar", headerPath(info, debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", headerPath(info, cldebuginfo100_insts_file), 
        "--operand-kinds-output", operand_kinds_file, 
        "--output-language", "c++" 
    };

    runPython(info.b.allocator, args, "Failed to build SPIR-V core tables");
}

fn genSPIRVCoreEnums(info: HeaderGenInfo, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(info, version, "spirv.core.grammar.json");

    const extension_enum_file = spirv_output_path ++ "/extension_enum.inc";
    const extension_map_file = spirv_output_path ++ "/enum_string_mapping.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", headerPath(info, debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", headerPath(info, cldebuginfo100_insts_file), 
        "--extension-enum-output", extension_enum_file, 
        "--enum-string-mapping-output", extension_map_file, 
        "--output-language", "c++"
    };

    runPython(info.b.allocator, args, "Failed to build SPIR-V core enums");
}

fn genSPIRVGlslTables(info: HeaderGenInfo, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(info, version, "spirv.core.grammar.json");
    const glsl_json_file = spvHeaderFile(info, version, "extinst.glsl.std.450.grammar.json");

    const glsl_insts_file = spirv_output_path ++ "/glsl.std.450.insts.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", headerPath(info, debuginfo_insts_file), 
        "--extinst-cldebuginfo100-grammar", headerPath(info, cldebuginfo100_insts_file), 
        "--extinst-glsl-grammar", glsl_json_file, 
        "--glsl-insts-output", glsl_insts_file, 
        "--output-language", "c++" 
    };

    runPython(info.b.allocator, args, "Failed to build SPIR-V GLSL tables");
}

fn genSPIRVOpenCLTables(info: HeaderGenInfo, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(info, version, "spirv.core.grammar.json");
    const opencl_json_file = spvHeaderFile(info, version, "extinst.opencl.std.100.grammar.json");

    const opencl_insts_file = spirv_output_path ++ "/opencl.std.insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--spirv-core-grammar", core_json_file,
        "--extinst-debuginfo-grammar", headerPath(info, debuginfo_insts_file),
        "--extinst-cldebuginfo100-grammar", headerPath(info, cldebuginfo100_insts_file),
        "--extinst-opencl-grammar", opencl_json_file,
        "--opencl-insts-output", opencl_insts_file,
    };

    runPython(info.b.allocator, args, "Failed to build SPIR-V OpenCL tables");
}

fn genSPIRVLanguageHeader(info: HeaderGenInfo, comptime name: []const u8, grammar_file: []const u8) void {
    const extinst_output_path = spirv_output_path ++ "/" ++ name ++ ".h";

    const args = &[_][]const u8{
        "python3", language_headers_script,
        "--extinst-grammar", grammar_file,
        "--extinst-output-path", extinst_output_path,
    };

    runPython(info.b.allocator, args, "Failed to generate SPIR-V language header '" ++ name);
}

fn genSPIRVVendorTable(info: HeaderGenInfo, comptime name: []const u8, comptime operand_kind_tools_prefix: []const u8) void {
    const extinst_vendor_grammar = headerPath(info, "include/spirv/unified1/extinst." ++ name ++ ".grammar.json");
    const extinst_file = spirv_output_path ++ "/" ++ name ++ ".insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--extinst-vendor-grammar", extinst_vendor_grammar,
        "--vendor-insts-output", extinst_file,
        "--vendor-operand-kind-prefix", operand_kind_tools_prefix,
    };

    runPython(info.b.allocator, args, "Failed to generate SPIR-V vendor table '" ++ name);
}

fn genSPIRVRegistryTables(info: HeaderGenInfo) void {
    const xml_file = headerPath(info, "include/spirv/spir-v.xml");
    const inc_file = spirv_output_path ++ "/generators.inc";

    const args = &[_][]const u8{
        "python3", gen_registry_tables_script,
        "--xml", xml_file,
        "--generator", inc_file,
    };

    runPython(info.b.allocator, args, "Failed to generate SPIR-V registry tables");
}

fn buildSPIRVVersion(info: HeaderGenInfo) void {
    const changes_file = "./CHANGES";
    const inc_file = spirv_output_path ++ "/build-version.inc";

    const args = &[_][]const u8{
        "python3", build_version_script,
        changes_file,
        inc_file,
    };

    runPython(info.b.allocator, args, "Failed to generate SPIR-V build version");
}

pub fn generateSPIRVHeaders(b: *Build, header_path: []const u8) void {
    const gen_info: HeaderGenInfo = .{
        .b = b,
        .header_path = header_path
    };

    if (!ensureCommandExists(b.allocator, "python3", "--version")) {
        log.err("'python3 --version' failed. Is python not installed?", .{});
        std.process.exit(1);
    }

    genSPIRVCoreTables(gen_info, "unified1");
    genSPIRVCoreEnums(gen_info, "unified1");

    genSPIRVGlslTables(gen_info, "1.0");

    genSPIRVOpenCLTables(gen_info, "1.0");

    genSPIRVLanguageHeader(gen_info, "DebugInfo", spvHeaderFile(gen_info, "unified1", "extinst.debuginfo.grammar.json"));
    genSPIRVLanguageHeader(gen_info, "OpenCLDebugInfo100", spvHeaderFile(gen_info, "unified1", "extinst.opencl.debuginfo.100.grammar.json"));
    genSPIRVLanguageHeader(gen_info, "NonSemanticShaderDebugInfo100", spvHeaderFile(gen_info, "unified1", "extinst.nonsemantic.shader.debuginfo.100.grammar.json"));

    genSPIRVVendorTable(gen_info, "spv-amd-shader-explicit-vertex-parameter", "...nil...");
    genSPIRVVendorTable(gen_info, "spv-amd-shader-trinary-minmax", "...nil...");
    genSPIRVVendorTable(gen_info, "spv-amd-gcn-shader", "...nil...");
    genSPIRVVendorTable(gen_info, "spv-amd-shader-ballot", "...nil...");
    genSPIRVVendorTable(gen_info, "debuginfo", "...nil...");
    genSPIRVVendorTable(gen_info, "opencl.debuginfo.100", "CLDEBUG100_");
    genSPIRVVendorTable(gen_info, "nonsemantic.clspvreflection", "...nil...");
    genSPIRVVendorTable(gen_info, "nonsemantic.vkspreflection", "...nil...");
    genSPIRVVendorTable(gen_info, "nonsemantic.shader.debuginfo.100", "SHDEBUG100_");

    genSPIRVRegistryTables(gen_info);

    buildSPIRVVersion(gen_info);
}