const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils/utils.zig");
const Build = std.Build;

pub const spv_headers_repo = "https://github.com/KhronosGroup/SPIRV-Headers";

const log = std.log.scoped(.spirv_tools);

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn runPython(allocator: std.mem.Allocator, args: []const []const u8, errMsg: []const u8) void {
    utils.execSilent(allocator, args, sdkPath("/")) catch |err|
    {
        log.err("{s}. error: {s}", .{ errMsg, @errorName(err) });
        std.process.exit(1);
    };
}

// ------------------------------------------
// SPIR-V include generation logic
// ------------------------------------------

pub const spirv_headers_path = "external/SPIRV-Headers";
pub const spirv_output_path = "build_spv_headers";

const grammar_tables_script = "utils/generate_grammar_tables.py";
const language_headers_script = "utils/generate_language_headers.py";
const build_version_script = "utils/update_build_version.py";
const gen_registry_tables_script = "utils/generate_registry_tables.py";

const debuginfo_insts_file = spirv_headers_path ++ "/include/spirv/unified1/extinst.debuginfo.grammar.json";
const cldebuginfo100_insts_file = spirv_headers_path ++ "/include/spirv/unified1/extinst.opencl.debuginfo.100.grammar.json";

fn spvHeaderFile(comptime version: []const u8, comptime file_name: []const u8) []const u8 {
    return spirv_headers_path ++ "/include/spirv/" ++ version ++ "/" ++ file_name;
}

// Script usage derived from the BUILD.gn

fn genSPIRVCoreTables(allocator: std.mem.Allocator, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json");

    // Outputs
    const core_insts_file = spirv_output_path ++ "/core.insts-" ++ version ++ ".inc";
    const operand_kinds_file = spirv_output_path ++ "/operand.kinds-" ++ version ++ ".inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--core-insts-output", core_insts_file, 
        "--extinst-debuginfo-grammar", debuginfo_insts_file, 
        "--extinst-cldebuginfo100-grammar", cldebuginfo100_insts_file, 
        "--operand-kinds-output", operand_kinds_file, 
        "--output-language", "c++" 
    };

    runPython(allocator, args, "Failed to build SPIR-V core tables");
}

fn genSPIRVCoreEnums(allocator: std.mem.Allocator, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json");

    const extension_enum_file = spirv_output_path ++ "/extension_enum.inc";
    const extension_map_file = spirv_output_path ++ "/enum_string_mapping.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", debuginfo_insts_file, 
        "--extinst-cldebuginfo100-grammar", cldebuginfo100_insts_file, 
        "--extension-enum-output", extension_enum_file, 
        "--enum-string-mapping-output", extension_map_file, 
        "--output-language", "c++"
    };

    runPython(allocator, args, "Failed to build SPIR-V core enums");
}

fn genSPIRVGlslTables(allocator: std.mem.Allocator, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json");
    const glsl_json_file = spvHeaderFile(version, "extinst.glsl.std.450.grammar.json");

    const glsl_insts_file = spirv_output_path ++ "/glsl.std.450.insts.inc";

    const args = &[_][]const u8{ 
        "python3", grammar_tables_script, 
        "--spirv-core-grammar", core_json_file, 
        "--extinst-debuginfo-grammar", debuginfo_insts_file, 
        "--extinst-cldebuginfo100-grammar", cldebuginfo100_insts_file, 
        "--extinst-glsl-grammar", glsl_json_file, 
        "--glsl-insts-output", glsl_insts_file, 
        "--output-language", "c++" 
    };

    runPython(allocator, args, "Failed to build SPIR-V GLSL tables");
}

fn genSPIRVOpenCLTables(allocator: std.mem.Allocator, comptime version: []const u8) void {
    const core_json_file = spvHeaderFile(version, "spirv.core.grammar.json");
    const opencl_json_file = spvHeaderFile(version, "extinst.opencl.std.100.grammar.json");

    const opencl_insts_file = spirv_output_path ++ "/opencl.std.insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--spirv-core-grammar", core_json_file,
        "--extinst-debuginfo-grammar", debuginfo_insts_file,
        "--extinst-cldebuginfo100-grammar", cldebuginfo100_insts_file,
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

fn genSPIRVVendorTable(allocator: std.mem.Allocator, comptime name: []const u8, comptime operand_kind_tools_prefix: []const u8) void {
    const extinst_vendor_grammar = spirv_headers_path ++ "/include/spirv/unified1/extinst." ++ name ++ ".grammar.json";
    const extinst_file = spirv_output_path ++ "/" ++ name ++ ".insts.inc";

    const args = &[_][]const u8{
        "python3", grammar_tables_script,
        "--extinst-vendor-grammar", extinst_vendor_grammar,
        "--vendor-insts-output", extinst_file,
        "--vendor-operand-kind-prefix", operand_kind_tools_prefix,
    };

    runPython(allocator, args, "Failed to generate SPIR-V vendor table '" ++ name);
}

fn genSPIRVRegistryTables(allocator: std.mem.Allocator) void {
    const xml_file = spirv_headers_path ++ "/include/spirv/spir-v.xml";
    const inc_file = spirv_output_path ++ "/generators.inc";

    const args = &[_][]const u8{
        "python3", gen_registry_tables_script,
        "--xml", xml_file,
        "--generator", inc_file,
    };

    runPython(allocator, args, "Failed to generate SPIR-V registry tables");
}

fn buildSPIRVVersion(allocator: std.mem.Allocator) void {
    const changes_file = "./CHANGES";
    const inc_file = spirv_output_path ++ "/build-version.inc";

    const args = &[_][]const u8{
        "python3", build_version_script,
        changes_file,
        inc_file,
    };

    runPython(allocator, args, "Failed to generate SPIR-V build version");
}

fn generateSPIRVHeaders(allocator: std.mem.Allocator) void {
    utils.ensureGitRepoCloned(allocator, spv_headers_repo, "", sdkPath("/external"), sdkPath("/external/SPIRV-Headers")) catch |err|
    {
        log.err("Could not clone git repo. error: {s}", .{ @errorName(err) });
        std.process.exit(1);
    };

    if (!utils.ensureCommandExists(allocator, "python3", "--version")) {
        log.err("'python3 --version' failed. Is python not installed?", .{});
        std.process.exit(1);
    }

    genSPIRVCoreTables(allocator, "unified1");
    genSPIRVCoreEnums(allocator, "unified1");

    genSPIRVGlslTables(allocator, "1.0");

    genSPIRVOpenCLTables(allocator, "1.0");

    genSPIRVLanguageHeader(allocator, "DebugInfo", spvHeaderFile("unified1", "extinst.debuginfo.grammar.json"));
    genSPIRVLanguageHeader(allocator, "OpenCLDebugInfo100", spvHeaderFile("unified1", "extinst.opencl.debuginfo.100.grammar.json"));
    genSPIRVLanguageHeader(allocator, "NonSemanticShaderDebugInfo100", spvHeaderFile("unified1", "extinst.nonsemantic.shader.debuginfo.100.grammar.json"));

    genSPIRVVendorTable(allocator, "spv-amd-shader-explicit-vertex-parameter", "...nil...");
    genSPIRVVendorTable(allocator, "spv-amd-shader-trinary-minmax", "...nil...");
    genSPIRVVendorTable(allocator, "spv-amd-gcn-shader", "...nil...");
    genSPIRVVendorTable(allocator, "spv-amd-shader-ballot", "...nil...");
    genSPIRVVendorTable(allocator, "debuginfo", "...nil...");
    genSPIRVVendorTable(allocator, "opencl.debuginfo.100", "CLDEBUG100_");
    genSPIRVVendorTable(allocator, "nonsemantic.clspvreflection", "...nil...");
    genSPIRVVendorTable(allocator, "nonsemantic.vkspreflection", "...nil...");
    genSPIRVVendorTable(allocator, "nonsemantic.shader.debuginfo.100", "SHDEBUG100_");

    genSPIRVRegistryTables(allocator);

    buildSPIRVVersion(allocator);
}

var build_mutex = std.Thread.Mutex{};

pub const BuildSPIRVHeadersStep = struct {
    step: std.Build.Step,
    b: *std.Build,

    pub fn init(b: *std.Build) *BuildSPIRVHeadersStep {
        const build_headers = b.allocator.create(BuildSPIRVHeadersStep) catch unreachable;

        build_headers.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "generate grammar",
                .owner = b,
                .makeFn = &make,
            }),
            .b = b,
        };

        return build_headers;
    }

    fn make(step_ptr: *std.Build.Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = prog_node;

        const build_headers: *BuildSPIRVHeadersStep = @fieldParentPtr("step", step_ptr);
        const b = build_headers.b;

        // Zig will run build steps in parallel if possible, so if there were two invocations of
        // then this function would be called in parallel. We're manipulating the FS here
        // and so need to prevent that.
        build_mutex.lock();
        defer build_mutex.unlock();

        generateSPIRVHeaders(b.allocator);
    }
};
