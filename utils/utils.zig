const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.utility);


pub fn ensureCommandExists(allocator: std.mem.Allocator, name: []const u8, exist_check: []const u8) bool {
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


pub fn exec(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    log.info("cd {s}", .{cwd});

    var buf = std.ArrayList(u8).init(allocator);
    for (argv) |arg| {
        try std.fmt.format(buf.writer(), "{s} ", .{arg});
    }

    log.info("{s}", .{buf.items});

    var child = std.ChildProcess.init(argv, allocator);
    child.cwd = cwd;
    _ = try child.spawnAndWait();
}


pub fn execSilent(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    for (argv) |arg| {
        try std.fmt.format(buf.writer(), "{s} ", .{arg});
    }

    var child = std.ChildProcess.init(argv, allocator);
    child.cwd = cwd;
    _ = try child.spawnAndWait();
}


pub fn ensureGit(allocator: std.mem.Allocator) void {
    if (!ensureCommandExists(allocator, "git", "--version")) {
        log.err("'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    }
}


pub fn isEnvVarTruthy(allocator: std.mem.Allocator, name: []const u8) bool {
    if (std.process.getEnvVarOwned(allocator, name)) |truthy| {
        defer allocator.free(truthy);
        if (std.mem.eql(u8, truthy, "true")) return true;
        return false;
    } else |_| {
        return false;
    }
}


pub fn ensureGitRepoCloned(allocator: std.mem.Allocator, clone_url: []const u8, revision: []const u8, parent_dir: []const u8, repo_dir: []const u8) !void {
    if (isEnvVarTruthy(allocator, "NO_ENSURE_SUBMODULES") or isEnvVarTruthy(allocator, "NO_ENSURE_GIT")) {
        return;
    }

    ensureGit(allocator);

    if (std.fs.openDirAbsolute(repo_dir, .{})) |_| {

        // Get latest version
        if (std.mem.eql(u8, revision, ""))
        {
            exec(allocator, &[_][]const u8{ "git", "pull" }, repo_dir) catch |err| log.warn("failed to 'git fetch' in {s}: {s}\n", .{ repo_dir, @errorName(err) });
            try exec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, repo_dir);
            return;
        }

        const current_revision = try getCurrentGitRevision(allocator, repo_dir);
        if (!std.mem.eql(u8, current_revision, revision)) {
            // Reset to the desired revision
            exec(allocator, &[_][]const u8{ "git", "fetch" }, repo_dir) catch |err| log.warn("failed to 'git fetch' in {s}: {s}\n", .{ repo_dir, @errorName(err) });
            try exec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, repo_dir);
            try exec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, repo_dir);
        }
        return;
    } else |err| return switch (err) {
        error.FileNotFound => {
            log.info("cloning required dependency..\ngit clone {s} {s}..\n", .{ clone_url, repo_dir });

            try exec(allocator, &[_][]const u8{ "git", "clone", "-c", "core.longpaths=true", clone_url, repo_dir }, parent_dir);

            if (!std.mem.eql(u8, revision, "")) {
                try exec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, repo_dir);
            }

            try exec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, repo_dir);

            return;
        },
        else => err,
    };
}


pub fn getCurrentGitRevision(allocator: std.mem.Allocator, cwd: []const u8) ![]const u8 {
    const result = try std.ChildProcess.run(.{ .allocator = allocator, .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = cwd });
    allocator.free(result.stderr);
    if (result.stdout.len > 0) return result.stdout[0 .. result.stdout.len - 1]; // trim newline
    return result.stdout;
}