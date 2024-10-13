const std = @import("std");
const builtin = @import("builtin");
const headers = @import("gen_headers.zig");
const Build = std.Build;

const log = std.log.scoped(.spirv_tools_zig);


pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const debug = b.option(bool, "debug", "Whether to produce detailed debug symbols (g0) or not. These increase binary size considerably.") orelse false;
    const shared = b.option(bool, "shared", "Build spirv-tools as a shared library") orelse false;
    const rebuild_headers = b.option(bool, "rebuild_headers", "Rebuild generated SPIRV-Headers. Requires python3 to be installed on the system.") orelse false;
    const header_path = b.option([]const u8, "header_path", "Specify a custom SPIRV-Headers installation path. Defaults to external/SPIRV-Headers. Non-root paths are relative to the SPIRV-Tools directory.") orelse "external/SPIRV-Headers";

    const no_val = b.option(bool, "no_val", "Skip building SPIRV-Tools-val") orelse false;
    const no_opt = b.option(bool, "no_opt", "Skip building SPIRV-Tools-opt") orelse false;
    const no_link = b.option(bool, "no_link", "Skip building SPIRV-Tools-link") orelse false;
    const no_reduce = b.option(bool, "no_reduce", "Skip building SPIRV-Tools-reduce") orelse false;

    var cppflags = std.ArrayList([]const u8).init(b.allocator);

    if (!debug) {
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
    };

    try cppflags.appendSlice(base_flags);

    var lib_args: BuildArgs = .{
        .cppflags = cppflags,
        .optimize = optimize,
        .target = target,
        .shared = shared,
        .name = "",
    };

    if (rebuild_headers) {
        headers.generateSPIRVHeaders(b, header_path);
    }

    if (!no_link and (no_val or no_opt)) {
        log.err("SPIRV-Tools-link requires building SPIRV-Tools-val and SPIRV-Tools-opt. Skip building link with -Dno_link or disable -Dno_val/-Dno_opt flags.", .{});
        std.process.exit(1);
    }

    if (!no_reduce and no_opt) {
        log.err("SPIRV-Tools-reduce requires building SPIRV-Tools-opt. Skip building reduce with -Dno_reduce or disable -Dno_opt flag.", .{});
        std.process.exit(1);
    }

    const header_include_path = pathAuto(b, b.pathJoin( &[_][]const u8{ header_path, "include" } ));

// ------------------
// SPIRV-Tools
// ------------------

    lib_args.name = "SPIRV-Tools";
    const tools = buildLibrary(b, &(spirv_tools ++ spirv_tools_util), lib_args, header_include_path);

    const install_tools_step = b.step("SPIRV-Tools", "Build and install SPIRV-Tools");
    install_tools_step.dependOn(&b.addInstallArtifact(tools, .{}).step);

    b.installArtifact(tools);

// ------------------
// SPIRV-Tools-val
// ------------------

    var tools_val: *Build.Step.Compile = undefined;
    if (!no_val)
    {
        lib_args.name = "SPIRV-Tools-val";
        tools_val = buildLibrary(b, &spirv_tools_val, lib_args, header_include_path);

        tools_val.linkLibrary(tools);

        const install_val_step = b.step("SPIRV-Tools-val", "Build and install SPIRV-Tools-val");
        install_val_step.dependOn(&b.addInstallArtifact(tools_val, .{}).step);

        b.installArtifact(tools_val);
    }

// ------------------
// SPIRV-Tools-opt
// ------------------

    var tools_opt: *Build.Step.Compile = undefined;
    if (!no_opt)
    {
        lib_args.name = "SPIRV-Tools-opt";
        tools_opt = buildLibrary(b, &spirv_tools_opt, lib_args, header_include_path);

        tools_opt.linkLibrary(tools);

        const install_opt_step = b.step("SPIRV-Tools-opt", "Build and install SPIRV-Tools-opt");
        install_opt_step.dependOn(&b.addInstallArtifact(tools_opt, .{}).step);

        b.installArtifact(tools_opt);
    }

// ------------------
// SPIRV-Tools-link
// ------------------

    if (!no_link)
    {
        lib_args.name = "SPIRV-Tools-link";
        const tools_link = buildLibrary(b, &spirv_tools_link, lib_args, header_include_path);

        tools_link.linkLibrary(tools);
        tools_link.linkLibrary(tools_val);
        tools_link.linkLibrary(tools_opt);

        const install_link_step = b.step("SPIRV-Tools-link", "Build and install SPIRV-Tools-link");
        install_link_step.dependOn(&b.addInstallArtifact(tools_link, .{}).step);

        b.installArtifact(tools_link);
    }

// ------------------
// SPIRV-Tools-reduce
// ------------------

    if (!no_reduce)
    {
        lib_args.name = "SPIRV-Tools-reduce";
        const tools_reduce = buildLibrary(b, &spirv_tools_reduce, lib_args, header_include_path);

        tools_reduce.linkLibrary(tools);
        tools_reduce.linkLibrary(tools_opt);

        const install_reduce_step = b.step("SPIRV-Tools-reduce", "Build and install SPIRV-Tools-reduce");
        install_reduce_step.dependOn(&b.addInstallArtifact(tools_reduce, .{}).step);

        b.installArtifact(tools_reduce);
    }
}


const BuildArgs = struct {
    cppflags: std.ArrayList([]const u8),
    optimize: std.builtin.OptimizeMode, 
    target: std.Build.ResolvedTarget,
    shared: bool, 
    name: []const u8, 
}; 


fn buildLibrary(b: *Build, sources: []const []const u8, args: BuildArgs, header_path: Build.LazyPath) *std.Build.Step.Compile {
    var lib: *std.Build.Step.Compile = undefined;

    if (args.shared) {
        lib = b.addSharedLibrary(.{
            .name = args.name,
            .optimize = args.optimize,
            .target = args.target,
        });

        lib.defineCMacro("SPIRV_TOOLS_IMPLEMENTATION", "");
        lib.defineCMacro("SPIRV_TOOLS_SHAREDLIB", "");
    } else {
        lib = b.addStaticLibrary(.{
            .name = args.name,
            .optimize = args.optimize,
            .target = args.target,
        });
    }

    const tag = args.target.result.os.tag;

    if (tag == .windows) {
        lib.defineCMacro("SPIRV_WINDOWS", "");
    } else if (tag == .linux) {
        lib.defineCMacro("SPIRV_LINUX", "");
    } else if (tag == .macos) {
        lib.defineCMacro("SPIRV_MAC", "");
    } else if (tag == .ios) {
        lib.defineCMacro("SPIRV_IOS", "");
    } else if (tag == .tvos) {
        lib.defineCMacro("SPIRV_TVOS", "");
    } else if (tag == .kfreebsd) {
        lib.defineCMacro("SPIRV_FREEBSD", "");
    } else if (tag == .openbsd) {
        lib.defineCMacro("SPIRV_OPENBSD", "");
    } else if (tag == .fuchsia) {
        lib.defineCMacro("SPIRV_FUCHSIA", "");
    } else {
        log.err("Compilation target incompatible with SPIR-V.", .{});
        std.process.exit(1);
    }

    lib.addCSourceFiles(.{
        .files = sources,
        .flags = args.cppflags.items,
    });

    lib.defineCMacro("SPIRV_COLOR_TERMINAL", ""); // Pretty lights on by default

    lib.addIncludePath(b.path(""));
    lib.addIncludePath(b.path(headers.spirv_output_path));

    lib.addIncludePath(header_path);
    lib.addIncludePath(b.path("include"));

    lib.linkLibCpp();
    lib.pie = true;

    return lib;
}


fn pathAuto(b: *Build, path: []const u8) Build.LazyPath {
    if (std.fs.path.isAbsolute(path)) {
        return .{ .cwd_relative = path };
    }
    return .{ .src_path = .{
        .owner = b,
        .sub_path = path,
    } };
}

// Source files pulled from BUILD.gn and CMakeLists.txt definitions

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
    "source/to_string.cpp",
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
    "source/opt/opextinst_forward_ref_fixup_pass.cpp",
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
    "source/opt/struct_packing_pass.cpp",
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
