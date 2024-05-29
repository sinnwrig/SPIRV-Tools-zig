const std = @import("std");
const builtin = @import("builtin");
const headers = @import("generate_headers.zig");
const utils = @import("utils/utils.zig");
const Build = std.Build;

const log = std.log.scoped(.spirv_tools_zig);

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const debug_symbols = b.option(bool, "debug_symbols", "Whether to produce detailed debug symbols (g0) or not. These increase binary size considerably.") orelse false;
    const build_shared = b.option(bool, "shared", "Build spirv-tools as a shared library") orelse false;

    _ = build_spirv(b, optimize, target, debug_symbols, build_shared) catch |err|
    {
        log.err("Error building SPIRV-Tools: {s}", .{ @errorName(err) });
        std.process.exit(1);
    }; 
}

pub fn build_spirv(b: *Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget, debug_symbols: bool, build_shared: bool) !*std.Build.Step.Compile {
    var cflags = std.ArrayList([]const u8).init(b.allocator);
    var cppflags = std.ArrayList([]const u8).init(b.allocator);

    if (!debug_symbols) {
        try cflags.append("-g0");
        try cppflags.append("-g0");
    }

    try cppflags.append("-std=c++17");

    const base_flags = &.{ 
        "-Wno-unused-command-line-argument",
        "-Wno-unused-variable",
        "-Wno-missing-exception-spec",
        "-Wno-macro-redefined",
        "-Wno-unknown-attributes",
        "-Wno-implicit-fallthrough",
        "-Wno-newline-eof", 
        "-Wno-unreachable-code-break", 
        "-Wno-unreachable-code-return", 
        "-fPIC",
    };

    try cflags.appendSlice(base_flags);
    try cppflags.appendSlice(base_flags);

    const spirv_cpp_sources =
        spirv_tools ++
        spirv_tools_util ++
        spirv_tools_reduce ++
        spirv_tools_link ++
        spirv_tools_val ++
        // spirv_tools_wasm ++ // Wasm build support- requires emscripten toolchain
        spirv_tools_opt;

    var spv_lib: *std.Build.Step.Compile = undefined;

    if (build_shared) {
        spv_lib = b.addSharedLibrary(.{
            .name = "SPIRV-Tools",
            .root_source_file = b.addWriteFiles().add("empty.c", ""),
            .optimize = optimize,
            .target = target,
        });
    } else {
        spv_lib = b.addStaticLibrary(.{
            .name = "SPIRV-Tools",
            .root_source_file = b.addWriteFiles().add("empty.c", ""),
            .optimize = optimize,
            .target = target,
        });
    }

    if (target.result.os.tag == .windows) {
        spv_lib.defineCMacro("SPIRV_WINDOWS", "");
    } else if (target.result.os.tag == .linux) {
        spv_lib.defineCMacro("SPIRV_LINUX", "");
    } else if (target.result.os.tag == .macos) {
        spv_lib.defineCMacro("SPIRV_MAC", "");
    } else if (target.result.os.tag == .ios) {
        spv_lib.defineCMacro("SPIRV_IOS", "");
    } else if (target.result.os.tag == .tvos) {
        spv_lib.defineCMacro("SPIRV_TVOS", "");
    } else if (target.result.os.tag == .kfreebsd) {
        spv_lib.defineCMacro("SPIRV_FREEBSD", "");
    } else if (target.result.os.tag == .openbsd) {
        spv_lib.defineCMacro("SPIRV_OPENBSD", "");
    } else if (target.result.os.tag == .fuchsia) {
        spv_lib.defineCMacro("SPIRV_FUCHSIA", "");
    } else {
        log.err("Compilation target incompatible with SPIR-V.", .{});
        std.process.exit(1);
    }

    var build_headers = headers.BuildSPIRVHeadersStep.init(b);

    spv_lib.step.dependOn(&build_headers.step);

    spv_lib.addCSourceFiles(.{
        .files = &spirv_cpp_sources,
        .flags = cppflags.items,
    });

    spv_lib.defineCMacro("SPIRV_COLOR_TERMINAL", ""); // Pretty lights by default

    addSPIRVIncludes(spv_lib);
    spv_lib.linkLibCpp();

    b.installArtifact(spv_lib);

    return spv_lib;
}

fn addSPIRVIncludes(step: *std.Build.Step.Compile) void {
    step.addIncludePath(.{ .path = headers.spirv_output_path });

    step.addIncludePath(.{ .path = sdkPath("/") });
    step.addIncludePath(.{ .path = "include" });
    step.addIncludePath(.{ .path = "source" });

    step.addIncludePath(.{ .path = "external/SPIRV-Headers/include" });
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

const spirv_tools = [_][]const u8{
    "source/assembly_grammar.cpp",
    "source/binary.cpp",
    "source/diagnostic.cpp",
    "source/disassemble.cpp",
    "source/enum_string_mapping.cpp",
    "source/ext_inst.cpp",
    "source/extensions.cpp",
    "source/libspirv.cpp",
    "source/name_mapper.cpp",
    "source/opcode.cpp",
    "source/operand.cpp",
    "source/parsed_operand.cpp",
    "source/print.cpp",
    "source/spirv_endian.cpp",
    "source/spirv_fuzzer_options.cpp",
    "source/spirv_optimizer_options.cpp",
    "source/spirv_reducer_options.cpp",
    "source/spirv_target_env.cpp",
    "source/spirv_validator_options.cpp",
    "source/table.cpp",
    "source/text.cpp",
    "source/text_handler.cpp",
    "source/util/bit_vector.cpp",
    "source/util/parse_number.cpp",
    "source/util/string_utils.cpp",
    "source/util/timer.cpp",
};

const spirv_tools_reduce = [_][]const u8{
    "source/reduce/change_operand_reduction_opportunity.cpp",
    "source/reduce/change_operand_to_undef_reduction_opportunity.cpp",
    "source/reduce/conditional_branch_to_simple_conditional_branch_opportunity_finder.cpp",
    "source/reduce/conditional_branch_to_simple_conditional_branch_reduction_opportunity.cpp",
    "source/reduce/merge_blocks_reduction_opportunity.cpp",
    "source/reduce/merge_blocks_reduction_opportunity_finder.cpp",
    "source/reduce/operand_to_const_reduction_opportunity_finder.cpp",
    "source/reduce/operand_to_dominating_id_reduction_opportunity_finder.cpp",
    "source/reduce/operand_to_undef_reduction_opportunity_finder.cpp",
    "source/reduce/reducer.cpp",
    "source/reduce/reduction_opportunity.cpp",
    "source/reduce/reduction_opportunity_finder.cpp",
    "source/reduce/reduction_pass.cpp",
    "source/reduce/reduction_util.cpp",
    "source/reduce/remove_block_reduction_opportunity.cpp",
    "source/reduce/remove_block_reduction_opportunity_finder.cpp",
    "source/reduce/remove_function_reduction_opportunity.cpp",
    "source/reduce/remove_function_reduction_opportunity_finder.cpp",
    "source/reduce/remove_instruction_reduction_opportunity.cpp",
    "source/reduce/remove_selection_reduction_opportunity.cpp",
    "source/reduce/remove_selection_reduction_opportunity_finder.cpp",
    "source/reduce/remove_struct_member_reduction_opportunity.cpp",
    "source/reduce/remove_unused_instruction_reduction_opportunity_finder.cpp",
    "source/reduce/remove_unused_struct_member_reduction_opportunity_finder.cpp",
    "source/reduce/simple_conditional_branch_to_branch_opportunity_finder.cpp",
    "source/reduce/simple_conditional_branch_to_branch_reduction_opportunity.cpp",
    "source/reduce/structured_construct_to_block_reduction_opportunity.cpp",
    "source/reduce/structured_construct_to_block_reduction_opportunity_finder.cpp",
    "source/reduce/structured_loop_to_selection_reduction_opportunity.cpp",
    "source/reduce/structured_loop_to_selection_reduction_opportunity_finder.cpp",
};

const spirv_tools_opt = [_][]const u8{
    "source/opt/aggressive_dead_code_elim_pass.cpp",
    "source/opt/amd_ext_to_khr.cpp",
    "source/opt/analyze_live_input_pass.cpp",
    "source/opt/basic_block.cpp",
    "source/opt/block_merge_pass.cpp",
    "source/opt/block_merge_util.cpp",
    "source/opt/build_module.cpp",
    "source/opt/ccp_pass.cpp",
    "source/opt/cfg.cpp",
    "source/opt/cfg_cleanup_pass.cpp",
    "source/opt/code_sink.cpp",
    "source/opt/combine_access_chains.cpp",
    "source/opt/compact_ids_pass.cpp",
    "source/opt/composite.cpp",
    "source/opt/const_folding_rules.cpp",
    "source/opt/constants.cpp",
    "source/opt/control_dependence.cpp",
    "source/opt/convert_to_half_pass.cpp",
    "source/opt/convert_to_sampled_image_pass.cpp",
    "source/opt/copy_prop_arrays.cpp",
    "source/opt/dataflow.cpp",
    "source/opt/dead_branch_elim_pass.cpp",
    "source/opt/dead_insert_elim_pass.cpp",
    "source/opt/dead_variable_elimination.cpp",
    "source/opt/debug_info_manager.cpp",
    "source/opt/decoration_manager.cpp",
    "source/opt/def_use_manager.cpp",
    "source/opt/desc_sroa.cpp",
    "source/opt/desc_sroa_util.cpp",
    "source/opt/dominator_analysis.cpp",
    "source/opt/dominator_tree.cpp",
    "source/opt/eliminate_dead_constant_pass.cpp",
    "source/opt/eliminate_dead_functions_pass.cpp",
    "source/opt/eliminate_dead_functions_util.cpp",
    "source/opt/eliminate_dead_io_components_pass.cpp",
    "source/opt/eliminate_dead_members_pass.cpp",
    "source/opt/eliminate_dead_output_stores_pass.cpp",
    "source/opt/feature_manager.cpp",
    "source/opt/fix_func_call_arguments.cpp",
    "source/opt/fix_storage_class.cpp",
    "source/opt/flatten_decoration_pass.cpp",
    "source/opt/fold.cpp",
    "source/opt/fold_spec_constant_op_and_composite_pass.cpp",
    "source/opt/folding_rules.cpp",
    "source/opt/freeze_spec_constant_value_pass.cpp",
    "source/opt/function.cpp",
    "source/opt/graphics_robust_access_pass.cpp",
    "source/opt/if_conversion.cpp",
    "source/opt/inline_exhaustive_pass.cpp",
    "source/opt/inline_opaque_pass.cpp",
    "source/opt/inline_pass.cpp",
    "source/opt/inst_debug_printf_pass.cpp",
    "source/opt/instruction.cpp",
    "source/opt/instruction_list.cpp",
    "source/opt/instrument_pass.cpp",
    "source/opt/interface_var_sroa.cpp",
    "source/opt/interp_fixup_pass.cpp",
    "source/opt/invocation_interlock_placement_pass.cpp",
    "source/opt/ir_context.cpp",
    "source/opt/ir_loader.cpp",
    "source/opt/licm_pass.cpp",
    "source/opt/liveness.cpp",
    "source/opt/local_access_chain_convert_pass.cpp",
    "source/opt/local_redundancy_elimination.cpp",
    "source/opt/local_single_block_elim_pass.cpp",
    "source/opt/local_single_store_elim_pass.cpp",
    "source/opt/loop_dependence.cpp",
    "source/opt/loop_dependence_helpers.cpp",
    "source/opt/loop_descriptor.cpp",
    "source/opt/loop_fission.cpp",
    "source/opt/loop_fusion.cpp",
    "source/opt/loop_fusion_pass.cpp",
    "source/opt/loop_peeling.cpp",
    "source/opt/loop_unroller.cpp",
    "source/opt/loop_unswitch_pass.cpp",
    "source/opt/loop_utils.cpp",
    "source/opt/mem_pass.cpp",
    "source/opt/merge_return_pass.cpp",
    "source/opt/modify_maximal_reconvergence.cpp",
    "source/opt/module.cpp",
    "source/opt/optimizer.cpp",
    "source/opt/pass.cpp",
    "source/opt/pass_manager.cpp",
    "source/opt/private_to_local_pass.cpp",
    "source/opt/propagator.cpp",
    "source/opt/reduce_load_size.cpp",
    "source/opt/redundancy_elimination.cpp",
    "source/opt/register_pressure.cpp",
    "source/opt/relax_float_ops_pass.cpp",
    "source/opt/remove_dontinline_pass.cpp",
    "source/opt/remove_duplicates_pass.cpp",
    "source/opt/remove_unused_interface_variables_pass.cpp",
    "source/opt/replace_desc_array_access_using_var_index.cpp",
    "source/opt/replace_invalid_opc.cpp",
    "source/opt/scalar_analysis.cpp",
    "source/opt/scalar_analysis_simplification.cpp",
    "source/opt/scalar_replacement_pass.cpp",
    "source/opt/set_spec_constant_default_value_pass.cpp",
    "source/opt/simplification_pass.cpp",
    "source/opt/spread_volatile_semantics.cpp",
    "source/opt/ssa_rewrite_pass.cpp",
    "source/opt/strength_reduction_pass.cpp",
    "source/opt/strip_debug_info_pass.cpp",
    "source/opt/strip_nonsemantic_info_pass.cpp",
    "source/opt/struct_cfg_analysis.cpp",
    "source/opt/switch_descriptorset_pass.cpp",
    "source/opt/trim_capabilities_pass.cpp",
    "source/opt/type_manager.cpp",
    "source/opt/types.cpp",
    "source/opt/unify_const_pass.cpp",
    "source/opt/upgrade_memory_model.cpp",
    "source/opt/value_number_table.cpp",
    "source/opt/vector_dce.cpp",
    "source/opt/workaround1209.cpp",
    "source/opt/wrap_opkill.cpp",
};

const spirv_tools_util = [_][]const u8{
    "source/util/bit_vector.cpp",
    "source/util/parse_number.cpp",
    "source/util/string_utils.cpp",
    "source/util/timer.cpp",
};

const spirv_tools_wasm = [_][]const u8{
    "source/wasm/spirv-tools.cpp",
};

const spirv_tools_link = [_][]const u8{
    "source/link/linker.cpp",
};

const spirv_tools_val = [_][]const u8{
    "source/val/basic_block.cpp",
    "source/val/construct.cpp",
    "source/val/function.cpp",
    "source/val/instruction.cpp",
    "source/val/validate.cpp",
    "source/val/validate_adjacency.cpp",
    "source/val/validate_annotation.cpp",
    "source/val/validate_arithmetics.cpp",
    "source/val/validate_atomics.cpp",
    "source/val/validate_barriers.cpp",
    "source/val/validate_bitwise.cpp",
    "source/val/validate_builtins.cpp",
    "source/val/validate_capability.cpp",
    "source/val/validate_cfg.cpp",
    "source/val/validate_composites.cpp",
    "source/val/validate_constants.cpp",
    "source/val/validate_conversion.cpp",
    "source/val/validate_debug.cpp",
    "source/val/validate_decorations.cpp",
    "source/val/validate_derivatives.cpp",
    "source/val/validate_execution_limitations.cpp",
    "source/val/validate_extensions.cpp",
    "source/val/validate_function.cpp",
    "source/val/validate_id.cpp",
    "source/val/validate_image.cpp",
    "source/val/validate_instruction.cpp",
    "source/val/validate_interfaces.cpp",
    "source/val/validate_layout.cpp",
    "source/val/validate_literals.cpp",
    "source/val/validate_logicals.cpp",
    "source/val/validate_memory.cpp",
    "source/val/validate_memory_semantics.cpp",
    "source/val/validate_mesh_shading.cpp",
    "source/val/validate_misc.cpp",
    "source/val/validate_mode_setting.cpp",
    "source/val/validate_non_uniform.cpp",
    "source/val/validate_primitives.cpp",
    "source/val/validate_ray_query.cpp",
    "source/val/validate_ray_tracing.cpp",
    "source/val/validate_ray_tracing_reorder.cpp",
    "source/val/validate_scopes.cpp",
    "source/val/validate_small_type_uses.cpp",
    "source/val/validate_type.cpp",
    "source/val/validation_state.cpp",
};
