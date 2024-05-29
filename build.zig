const std = @import("std");
const builtin = @import("builtin");
const headers = @import("generate_headers.zig");
const utils = @import("utils/utils.zig");
const Build = std.Build;

const log = std.log.scoped(.spirv_tools_zig);


pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const debug = b.option(bool, "debug", "Whether to produce detailed debug symbols (g0) or not. These increase binary size considerably.") orelse false;
    const shared = b.option(bool, "shared", "Build spirv-tools as a shared library") orelse false;

    _ = build_spirv(b, optimize, target, shared,  debug) catch |err| {
        log.err("Error building SPIRV-Tools: {s}", .{ @errorName(err) });
        std.process.exit(1);
    }; 
}


const SPVLibs = struct {
    tools: *std.Build.Step.Compile,
    tools_val: *std.Build.Step.Compile,
    tools_opt: *std.Build.Step.Compile,
    tools_link: *std.Build.Step.Compile,
    tools_reduce: *std.Build.Step.Compile
};


pub fn build_spirv(b: *Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget, shared: bool, debug: bool) !SPVLibs {
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
        "-fPIC",
    };

    try cppflags.appendSlice(base_flags);

    var libs: SPVLibs = undefined;

    var lib_args: BuildArgs = .{
        .cppflags = cppflags,
        .optimize = optimize,
        .target = target,
        .shared = shared,
        .name = "",
    };

// ------------------
// SPIRV-Tools
// ------------------

    const build_headers = headers.BuildSPIRVHeadersStep.init(b);    

    lib_args.name = "SPIRV-Tools";
    libs.tools = buildLibrary(b, &(spirv_tools ++ spirv_tools_util), lib_args);

    libs.tools.step.dependOn(&build_headers.step);

    const install_tools_step = b.step("SPIRV-Tools", "Build and install SPIRV-Tools");
    install_tools_step.dependOn(&b.addInstallArtifact(libs.tools, .{}).step);

    b.installArtifact(libs.tools);

// ------------------
// SPIRV-Tools-val
// ------------------

    lib_args.name = "SPIRV-Tools-val";
    libs.tools_val = buildLibrary(b, &spirv_tools_val, lib_args);

    libs.tools_val.linkLibrary(libs.tools);

    const install_val_step = b.step("SPIRV-Tools-val", "Build and install SPIRV-Tools-val");
    install_val_step.dependOn(&b.addInstallArtifact(libs.tools_val, .{}).step);

    b.installArtifact(libs.tools_val);

// ------------------
// SPIRV-Tools-opt
// ------------------

    lib_args.name = "SPIRV-Tools-opt";
    libs.tools_opt = buildLibrary(b, &spirv_tools_opt, lib_args);

    libs.tools_opt.linkLibrary(libs.tools);

    const install_opt_step = b.step("SPIRV-Tools-opt", "Build and install SPIRV-Tools-opt");
    install_opt_step.dependOn(&b.addInstallArtifact(libs.tools_opt, .{}).step);

    b.installArtifact(libs.tools_opt);

// ------------------
// SPIRV-Tools-link
// ------------------

    lib_args.name = "SPIRV-Tools-link";
    libs.tools_link = buildLibrary(b, &spirv_tools_link, lib_args);

    libs.tools_link.linkLibrary(libs.tools);
    libs.tools_link.linkLibrary(libs.tools_val);
    libs.tools_link.linkLibrary(libs.tools_opt);

    const install_link_step = b.step("SPIRV-Tools-link", "Build and install SPIRV-Tools-link");
    install_link_step.dependOn(&b.addInstallArtifact(libs.tools_link, .{}).step);

    b.installArtifact(libs.tools_link);

// ------------------
// SPIRV-Tools-reduce
// ------------------

    lib_args.name = "SPIRV-Tools-reduce";
    libs.tools_reduce = buildLibrary(b, &spirv_tools_reduce, lib_args);

    libs.tools_reduce.linkLibrary(libs.tools);
    libs.tools_reduce.linkLibrary(libs.tools_opt);
    
    const install_reduce_step = b.step("SPIRV-Tools-reduce", "Build and install SPIRV-Tools-reduce");
    install_reduce_step.dependOn(&b.addInstallArtifact(libs.tools_reduce, .{}).step);

    b.installArtifact(libs.tools_reduce);

    return libs;
}


const BuildArgs = struct {
    cppflags: std.ArrayList([]const u8),
    optimize: std.builtin.OptimizeMode, 
    target: std.Build.ResolvedTarget,
    shared: bool, 
    name: []const u8, 
}; 


fn buildLibrary(b: *Build, sources: []const []const u8, args: BuildArgs) *std.Build.Step.Compile {
    var lib: *std.Build.Step.Compile = undefined;

    if (args.shared) {
        lib = b.addSharedLibrary(.{
            .name = args.name,
            .root_source_file = b.addWriteFiles().add("empty.c", ""),
            .optimize = args.optimize,
            .target = args.target,
        });

        lib.defineCMacro("SPIRV_TOOLS_IMPLEMENTATION", "");
        lib.defineCMacro("SPIRV_TOOLS_SHAREDLIB", "");
    } else {
        lib = b.addStaticLibrary(.{
            .name = args.name,
            .root_source_file = b.addWriteFiles().add("empty.c", ""),
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

    lib.defineCMacro("SPIRV_COLOR_TERMINAL", ""); // Pretty lights by default

    addSPIRVIncludes(lib);

    lib.linkLibCpp();

    return lib;
}

// The stuff other libraries should have access to
pub fn addSPIRVPublicIncludes(step: *std.Build.Step.Compile) void {
    step.addIncludePath(.{ .path = "include" });
    step.addIncludePath(.{ .path = "external/SPIRV-Headers/include" });
}

// The stuff only source files should have access to
fn addSPIRVIncludes(step: *std.Build.Step.Compile) void {
    step.addIncludePath(.{ .path = headers.spirv_output_path });
    step.addIncludePath(.{ .path = sdkPath("/") });
    addSPIRVPublicIncludes(step);
}


fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}


// Source files pulled from BUILD.gn

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


const spirv_tools_fuzz = [_][]const u8{
    "source/fuzz/added_function_reducer.cpp",
    "source/fuzz/available_instructions.cpp",
    "source/fuzz/call_graph.cpp",
    "source/fuzz/counter_overflow_id_source.cpp",
    "source/fuzz/data_descriptor.cpp",
    "source/fuzz/fact_manager/constant_uniform_facts.cpp",
    "source/fuzz/fact_manager/data_synonym_and_id_equation_facts.cpp",
    "source/fuzz/fact_manager/dead_block_facts.cpp",
    "source/fuzz/fact_manager/fact_manager.cpp",
    "source/fuzz/fact_manager/irrelevant_value_facts.cpp",
    "source/fuzz/fact_manager/livesafe_function_facts.cpp",
    "source/fuzz/force_render_red.cpp",
    "source/fuzz/fuzzer.cpp",
    "source/fuzz/fuzzer_context.cpp",
    "source/fuzz/fuzzer_pass.cpp",
    "source/fuzz/fuzzer_pass_add_access_chains.cpp",
    "source/fuzz/fuzzer_pass_add_bit_instruction_synonyms.cpp",
    "source/fuzz/fuzzer_pass_add_composite_extract.cpp",
    "source/fuzz/fuzzer_pass_add_composite_inserts.cpp",
    "source/fuzz/fuzzer_pass_add_composite_types.cpp",
    "source/fuzz/fuzzer_pass_add_copy_memory.cpp",
    "source/fuzz/fuzzer_pass_add_dead_blocks.cpp",
    "source/fuzz/fuzzer_pass_add_dead_breaks.cpp",
    "source/fuzz/fuzzer_pass_add_dead_continues.cpp",
    "source/fuzz/fuzzer_pass_add_equation_instructions.cpp",
    "source/fuzz/fuzzer_pass_add_function_calls.cpp",
    "source/fuzz/fuzzer_pass_add_global_variables.cpp",
    "source/fuzz/fuzzer_pass_add_image_sample_unused_components.cpp",
    "source/fuzz/fuzzer_pass_add_loads.cpp",
    "source/fuzz/fuzzer_pass_add_local_variables.cpp",
    "source/fuzz/fuzzer_pass_add_loop_preheaders.cpp",
    "source/fuzz/fuzzer_pass_add_loops_to_create_int_constant_synonyms.cpp",
    "source/fuzz/fuzzer_pass_add_no_contraction_decorations.cpp",
    "source/fuzz/fuzzer_pass_add_opphi_synonyms.cpp",
    "source/fuzz/fuzzer_pass_add_parameters.cpp",
    "source/fuzz/fuzzer_pass_add_relaxed_decorations.cpp",
    "source/fuzz/fuzzer_pass_add_stores.cpp",
    "source/fuzz/fuzzer_pass_add_synonyms.cpp",
    "source/fuzz/fuzzer_pass_add_vector_shuffle_instructions.cpp",
    "source/fuzz/fuzzer_pass_adjust_branch_weights.cpp",
    "source/fuzz/fuzzer_pass_adjust_function_controls.cpp",
    "source/fuzz/fuzzer_pass_adjust_loop_controls.cpp",
    "source/fuzz/fuzzer_pass_adjust_memory_operands_masks.cpp",
    "source/fuzz/fuzzer_pass_adjust_selection_controls.cpp",
    "source/fuzz/fuzzer_pass_apply_id_synonyms.cpp",
    "source/fuzz/fuzzer_pass_construct_composites.cpp",
    "source/fuzz/fuzzer_pass_copy_objects.cpp",
    "source/fuzz/fuzzer_pass_donate_modules.cpp",
    "source/fuzz/fuzzer_pass_duplicate_regions_with_selections.cpp",
    "source/fuzz/fuzzer_pass_expand_vector_reductions.cpp",
    "source/fuzz/fuzzer_pass_flatten_conditional_branches.cpp",
    "source/fuzz/fuzzer_pass_inline_functions.cpp",
    "source/fuzz/fuzzer_pass_interchange_signedness_of_integer_operands.cpp",
    "source/fuzz/fuzzer_pass_interchange_zero_like_constants.cpp",
    "source/fuzz/fuzzer_pass_invert_comparison_operators.cpp",
    "source/fuzz/fuzzer_pass_make_vector_operations_dynamic.cpp",
    "source/fuzz/fuzzer_pass_merge_blocks.cpp",
    "source/fuzz/fuzzer_pass_merge_function_returns.cpp",
    "source/fuzz/fuzzer_pass_mutate_pointers.cpp",
    "source/fuzz/fuzzer_pass_obfuscate_constants.cpp",
    "source/fuzz/fuzzer_pass_outline_functions.cpp",
    "source/fuzz/fuzzer_pass_permute_blocks.cpp",
    "source/fuzz/fuzzer_pass_permute_function_parameters.cpp",
    "source/fuzz/fuzzer_pass_permute_function_variables.cpp",
    "source/fuzz/fuzzer_pass_permute_instructions.cpp",
    "source/fuzz/fuzzer_pass_permute_phi_operands.cpp",
    "source/fuzz/fuzzer_pass_propagate_instructions_down.cpp",
    "source/fuzz/fuzzer_pass_propagate_instructions_up.cpp",
    "source/fuzz/fuzzer_pass_push_ids_through_variables.cpp",
    "source/fuzz/fuzzer_pass_replace_adds_subs_muls_with_carrying_extended.cpp",
    "source/fuzz/fuzzer_pass_replace_branches_from_dead_blocks_with_exits.cpp",
    "source/fuzz/fuzzer_pass_replace_copy_memories_with_loads_stores.cpp",
    "source/fuzz/fuzzer_pass_replace_copy_objects_with_stores_loads.cpp",
    "source/fuzz/fuzzer_pass_replace_irrelevant_ids.cpp",
    "source/fuzz/fuzzer_pass_replace_linear_algebra_instructions.cpp",
    "source/fuzz/fuzzer_pass_replace_loads_stores_with_copy_memories.cpp",
    "source/fuzz/fuzzer_pass_replace_opphi_ids_from_dead_predecessors.cpp",
    "source/fuzz/fuzzer_pass_replace_opselects_with_conditional_branches.cpp",
    "source/fuzz/fuzzer_pass_replace_parameter_with_global.cpp",
    "source/fuzz/fuzzer_pass_replace_params_with_struct.cpp",
    "source/fuzz/fuzzer_pass_split_blocks.cpp",
    "source/fuzz/fuzzer_pass_swap_commutable_operands.cpp",
    "source/fuzz/fuzzer_pass_swap_conditional_branch_operands.cpp",
    "source/fuzz/fuzzer_pass_swap_functions.cpp",
    "source/fuzz/fuzzer_pass_toggle_access_chain_instruction.cpp",
    "source/fuzz/fuzzer_pass_wrap_regions_in_selections.cpp",
    "source/fuzz/fuzzer_pass_wrap_vector_synonym.cpp",
    "source/fuzz/fuzzer_util.cpp",
    "source/fuzz/id_use_descriptor.cpp",
    "source/fuzz/instruction_descriptor.cpp",
    "source/fuzz/instruction_message.cpp",
    "source/fuzz/overflow_id_source.cpp",
    "source/fuzz/pass_management/repeated_pass_manager.cpp",
    "source/fuzz/pass_management/repeated_pass_manager_looped_with_recommendations.cpp",
    "source/fuzz/pass_management/repeated_pass_manager_random_with_recommendations.cpp",
    "source/fuzz/pass_management/repeated_pass_manager_simple.cpp",
    "source/fuzz/pass_management/repeated_pass_recommender.cpp",
    "source/fuzz/pass_management/repeated_pass_recommender_standard.cpp",
    "source/fuzz/pseudo_random_generator.cpp",
    "source/fuzz/random_generator.cpp",
    "source/fuzz/replayer.cpp",
    "source/fuzz/shrinker.cpp",
    "source/fuzz/transformation.cpp",
    "source/fuzz/transformation_access_chain.cpp",
    "source/fuzz/transformation_add_bit_instruction_synonym.cpp",
    "source/fuzz/transformation_add_constant_boolean.cpp",
    "source/fuzz/transformation_add_constant_composite.cpp",
    "source/fuzz/transformation_add_constant_null.cpp",
    "source/fuzz/transformation_add_constant_scalar.cpp",
    "source/fuzz/transformation_add_copy_memory.cpp",
    "source/fuzz/transformation_add_dead_block.cpp",
    "source/fuzz/transformation_add_dead_break.cpp",
    "source/fuzz/transformation_add_dead_continue.cpp",
    "source/fuzz/transformation_add_early_terminator_wrapper.cpp",
    "source/fuzz/transformation_add_function.cpp",
    "source/fuzz/transformation_add_global_undef.cpp",
    "source/fuzz/transformation_add_global_variable.cpp",
    "source/fuzz/transformation_add_image_sample_unused_components.cpp",
    "source/fuzz/transformation_add_local_variable.cpp",
    "source/fuzz/transformation_add_loop_preheader.cpp",
    "source/fuzz/transformation_add_loop_to_create_int_constant_synonym.cpp",
    "source/fuzz/transformation_add_no_contraction_decoration.cpp",
    "source/fuzz/transformation_add_opphi_synonym.cpp",
    "source/fuzz/transformation_add_parameter.cpp",
    "source/fuzz/transformation_add_relaxed_decoration.cpp",
    "source/fuzz/transformation_add_spec_constant_op.cpp",
    "source/fuzz/transformation_add_synonym.cpp",
    "source/fuzz/transformation_add_type_array.cpp",
    "source/fuzz/transformation_add_type_boolean.cpp",
    "source/fuzz/transformation_add_type_float.cpp",
    "source/fuzz/transformation_add_type_function.cpp",
    "source/fuzz/transformation_add_type_int.cpp",
    "source/fuzz/transformation_add_type_matrix.cpp",
    "source/fuzz/transformation_add_type_pointer.cpp",
    "source/fuzz/transformation_add_type_struct.cpp",
    "source/fuzz/transformation_add_type_vector.cpp",
    "source/fuzz/transformation_adjust_branch_weights.cpp",
    "source/fuzz/transformation_composite_construct.cpp",
    "source/fuzz/transformation_composite_extract.cpp",
    "source/fuzz/transformation_composite_insert.cpp",
    "source/fuzz/transformation_compute_data_synonym_fact_closure.cpp",
    "source/fuzz/transformation_context.cpp",
    "source/fuzz/transformation_duplicate_region_with_selection.cpp",
    "source/fuzz/transformation_equation_instruction.cpp",
    "source/fuzz/transformation_expand_vector_reduction.cpp",
    "source/fuzz/transformation_flatten_conditional_branch.cpp",
    "source/fuzz/transformation_function_call.cpp",
    "source/fuzz/transformation_inline_function.cpp",
    "source/fuzz/transformation_invert_comparison_operator.cpp",
    "source/fuzz/transformation_load.cpp",
    "source/fuzz/transformation_make_vector_operation_dynamic.cpp",
    "source/fuzz/transformation_merge_blocks.cpp",
    "source/fuzz/transformation_merge_function_returns.cpp",
    "source/fuzz/transformation_move_block_down.cpp",
    "source/fuzz/transformation_move_instruction_down.cpp",
    "source/fuzz/transformation_mutate_pointer.cpp",
    "source/fuzz/transformation_outline_function.cpp",
    "source/fuzz/transformation_permute_function_parameters.cpp",
    "source/fuzz/transformation_permute_phi_operands.cpp",
    "source/fuzz/transformation_propagate_instruction_down.cpp",
    "source/fuzz/transformation_propagate_instruction_up.cpp",
    "source/fuzz/transformation_push_id_through_variable.cpp",
    "source/fuzz/transformation_record_synonymous_constants.cpp",
    "source/fuzz/transformation_replace_add_sub_mul_with_carrying_extended.cpp",
    "source/fuzz/transformation_replace_boolean_constant_with_constant_binary.cpp",
    "source/fuzz/transformation_replace_branch_from_dead_block_with_exit.cpp",
    "source/fuzz/transformation_replace_constant_with_uniform.cpp",
    "source/fuzz/transformation_replace_copy_memory_with_load_store.cpp",
    "source/fuzz/transformation_replace_copy_object_with_store_load.cpp",
    "source/fuzz/transformation_replace_id_with_synonym.cpp",
    "source/fuzz/transformation_replace_irrelevant_id.cpp",
    "source/fuzz/transformation_replace_linear_algebra_instruction.cpp",
    "source/fuzz/transformation_replace_load_store_with_copy_memory.cpp",
    "source/fuzz/transformation_replace_opphi_id_from_dead_predecessor.cpp",
    "source/fuzz/transformation_replace_opselect_with_conditional_branch.cpp",
    "source/fuzz/transformation_replace_parameter_with_global.cpp",
    "source/fuzz/transformation_replace_params_with_struct.cpp",
    "source/fuzz/transformation_set_function_control.cpp",
    "source/fuzz/transformation_set_loop_control.cpp",
    "source/fuzz/transformation_set_memory_operands_mask.cpp",
    "source/fuzz/transformation_set_selection_control.cpp",
    "source/fuzz/transformation_split_block.cpp",
    "source/fuzz/transformation_store.cpp",
    "source/fuzz/transformation_swap_commutable_operands.cpp",
    "source/fuzz/transformation_swap_conditional_branch_operands.cpp",
    "source/fuzz/transformation_swap_function_variables.cpp",
    "source/fuzz/transformation_swap_two_functions.cpp",
    "source/fuzz/transformation_toggle_access_chain_instruction.cpp",
    "source/fuzz/transformation_vector_shuffle.cpp",
    "source/fuzz/transformation_wrap_early_terminator_in_function.cpp",
    "source/fuzz/transformation_wrap_region_in_selection.cpp",
    "source/fuzz/transformation_wrap_vector_synonym.cpp",
    "source/fuzz/uniform_buffer_element_descriptor.cpp",
};