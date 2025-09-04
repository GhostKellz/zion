const std = @import("std");
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;
const ZionConfig = @import("enhanced_config.zig").ZionConfig;

/// Neovim integration for zion - provides Lua API for zion-nvim plugin
pub const NvimIntegration = struct {
    allocator: Allocator,
    config: ZionConfig,
    
    pub fn init(allocator: Allocator) !NvimIntegration {
        const config = try ZionConfig.load(allocator);
        return NvimIntegration{
            .allocator = allocator,
            .config = config,
        };
    }
    
    pub fn deinit(self: *NvimIntegration) void {
        self.config.deinit();
    }
    
    /// Handle Neovim RPC calls
    pub fn handleRpcCall(self: *NvimIntegration, method: []const u8, params: json.Value) !json.Value {
        if (std.mem.eql(u8, method, "add_dependency")) {
            return self.addDependencyRpc(params);
        } else if (std.mem.eql(u8, method, "remove_dependency")) {
            return self.removeDependencyRpc(params);
        } else if (std.mem.eql(u8, method, "list_dependencies")) {
            return self.listDependenciesRpc();
        } else if (std.mem.eql(u8, method, "check_project")) {
            return self.checkProjectRpc();
        } else if (std.mem.eql(u8, method, "search_packages")) {
            return self.searchPackagesRpc(params);
        } else if (std.mem.eql(u8, method, "get_config")) {
            return self.getConfigRpc();
        } else if (std.mem.eql(u8, method, "update_dependencies")) {
            return self.updateDependenciesRpc();
        } else if (std.mem.eql(u8, method, "switch_zig_version")) {
            return self.switchZigVersionRpc(params);
        } else {
            return json.Value{ .object = json.ObjectMap.init(self.allocator) };
        }
    }
    
    /// Add dependency from Neovim
    fn addDependencyRpc(self: *NvimIntegration, params: json.Value) !json.Value {
        const package_name = params.object.get("package") orelse return self.errorResponse("Missing package parameter");
        
        // Resolve package name using config
        const resolved_name = if (self.config.resolvePackageName(package_name.string)) |resolved|
            resolved
        else
            try self.allocator.dupe(u8, package_name.string);
        defer self.allocator.free(resolved_name);
        
        // Execute zion add command
        const result = try self.executeZionCommand(&[_][]const u8{ "add", resolved_name });
        defer self.allocator.free(result.output);
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = result.success });
        try response.put("output", json.Value{ .string = result.output });
        
        if (result.success) {
            try response.put("message", json.Value{ .string = "Dependency added successfully" });
        }
        
        return json.Value{ .object = response };
    }
    
    /// Remove dependency from Neovim
    fn removeDependencyRpc(self: *NvimIntegration, params: json.Value) !json.Value {
        const package_name = params.object.get("package") orelse return self.errorResponse("Missing package parameter");
        
        const result = try self.executeZionCommand(&[_][]const u8{ "remove", package_name.string });
        defer self.allocator.free(result.output);
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = result.success });
        try response.put("output", json.Value{ .string = result.output });
        
        return json.Value{ .object = response };
    }
    
    /// List project dependencies for Neovim
    fn listDependenciesRpc(self: *NvimIntegration) !json.Value {
        const result = try self.executeZionCommand(&[_][]const u8{ "list", "--json" });
        defer self.allocator.free(result.output);
        
        if (result.success) {
            // Parse the JSON output from zion list
            var parsed = try json.parseFromSlice(json.Value, self.allocator, result.output, .{});
            defer parsed.deinit();
            return parsed.value;
        } else {
            return self.errorResponse(result.output);
        }
    }
    
    /// Check project health for Neovim
    fn checkProjectRpc(self: *NvimIntegration) !json.Value {
        const result = try self.executeZionCommand(&[_][]const u8{"check"});
        defer self.allocator.free(result.output);
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = result.success });
        try response.put("output", json.Value{ .string = result.output });
        
        // Parse health status (simplified)
        const health_status = if (std.mem.indexOf(u8, result.output, "HEALTHY") != null)
            "healthy"
        else if (std.mem.indexOf(u8, result.output, "WARNINGS") != null)
            "warnings"
        else
            "errors";
            
        try response.put("status", json.Value{ .string = health_status });
        
        return json.Value{ .object = response };
    }
    
    /// Search packages for Neovim
    fn searchPackagesRpc(self: *NvimIntegration, params: json.Value) !json.Value {
        const query = params.object.get("query") orelse return self.errorResponse("Missing query parameter");
        
        // For now, return mock search results
        // In a full implementation, this would search GitHub or a package registry
        var results = json.Array.init(self.allocator);
        
        // Mock some results based on common Zig packages
        const mock_packages = [_]struct { name: []const u8, description: []const u8 }{
            .{ .name = "mitchellh/libxev", .description = "Cross-platform async I/O library" },
            .{ .name = "ziglang/zig", .description = "Zig programming language" },
            .{ .name = "ghostkellz/zcrypto", .description = "Cryptography library for Zig" },
        };
        
        for (mock_packages) |pkg| {
            if (std.mem.indexOf(u8, pkg.name, query.string) != null or 
                std.mem.indexOf(u8, pkg.description, query.string) != null) {
                
                var pkg_obj = json.ObjectMap.init(self.allocator);
                try pkg_obj.put("name", json.Value{ .string = pkg.name });
                try pkg_obj.put("description", json.Value{ .string = pkg.description });
                try results.append(json.Value{ .object = pkg_obj });
            }
        }
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("results", json.Value{ .array = results });
        try response.put("count", json.Value{ .integer = @intCast(results.items.len) });
        
        return json.Value{ .object = response };
    }
    
    /// Get zion configuration for Neovim
    fn getConfigRpc(self: *NvimIntegration) !json.Value {
        var config_obj = json.ObjectMap.init(self.allocator);
        
        if (self.config.github_username) |username| {
            try config_obj.put("github_username", json.Value{ .string = username });
        }
        
        var orgs_array = json.Array.init(self.allocator);
        for (self.config.github_orgs.items) |org| {
            try orgs_array.append(json.Value{ .string = org });
        }
        try config_obj.put("github_orgs", json.Value{ .array = orgs_array });
        
        try config_obj.put("auto_add_to_build", json.Value{ .bool = self.config.auto_add_to_build });
        try config_obj.put("neovim_integration", json.Value{ .bool = self.config.neovim_integration });
        
        return json.Value{ .object = config_obj };
    }
    
    /// Update all dependencies
    fn updateDependenciesRpc(self: *NvimIntegration) !json.Value {
        const result = try self.executeZionCommand(&[_][]const u8{"update"});
        defer self.allocator.free(result.output);
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = result.success });
        try response.put("output", json.Value{ .string = result.output });
        
        return json.Value{ .object = response };
    }
    
    /// Switch Zig version from Neovim
    fn switchZigVersionRpc(self: *NvimIntegration, params: json.Value) !json.Value {
        const version = params.object.get("version") orelse return self.errorResponse("Missing version parameter");
        
        const result = try self.executeZionCommand(&[_][]const u8{ "zig", "use", version.string });
        defer self.allocator.free(result.output);
        
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = result.success });
        try response.put("output", json.Value{ .string = result.output });
        
        return json.Value{ .object = response };
    }
    
    /// Execute a zion command and return the result
    fn executeZionCommand(self: *NvimIntegration, args: []const []const u8) !CommandResult {
        var cmd_args: std.ArrayList([]const u8) = .{};
        defer cmd_args.deinit(self.allocator);
        
        try cmd_args.append(self.allocator, "zion");
        for (args) |arg| {
            try cmd_args.append(self.allocator, arg);
        }
        
        var child = std.process.Child.init(cmd_args.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        var stdout_output_buf: std.ArrayList(u8) = .{};
        defer stdout_output_buf.deinit(self.allocator);
        
        var stdout_read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = try child.stdout.?.readAll(stdout_read_buf[0..]);
            if (bytes_read == 0) break;
            try stdout_output_buf.appendSlice(stdout_read_buf[0..bytes_read]);
        }
        
        const stdout = try self.allocator.dupe(u8, stdout_output_buf.items);
        
        var stderr_output_buf: std.ArrayList(u8) = .{};
        defer stderr_output_buf.deinit(self.allocator);
        
        var stderr_read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = try child.stderr.?.readAll(stderr_read_buf[0..]);
            if (bytes_read == 0) break;
            try stderr_output_buf.appendSlice(stderr_read_buf[0..bytes_read]);
        }
        
        const stderr = try self.allocator.dupe(u8, stderr_output_buf.items);
        defer self.allocator.free(stderr);
        
        const term = try child.wait();
        
        const success = switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
        
        const output = if (success) stdout else blk: {
            self.allocator.free(stdout);
            break :blk try self.allocator.dupe(u8, stderr);
        };
        
        return CommandResult{
            .success = success,
            .output = output,
        };
    }
    
    /// Create an error response
    fn errorResponse(self: *NvimIntegration, message: []const u8) !json.Value {
        var response = json.ObjectMap.init(self.allocator);
        try response.put("success", json.Value{ .bool = false });
        try response.put("error", json.Value{ .string = message });
        return json.Value{ .object = response };
    }
};

const CommandResult = struct {
    success: bool,
    output: []const u8,
};

/// Create Neovim plugin file for zion integration
pub fn createNvimPlugin(allocator: Allocator) !void {
    const plugin_content =
        \\-- Zion.nvim - Neovim integration for Zion package manager
        \\-- This file provides Lua functions for interacting with zion from Neovim
        \\
        \\local M = {}
        \\
        \\-- Internal state
        \\local zion_config = nil
        \\
        \\-- Load zion configuration
        \\local function load_config()
        \\  if zion_config then return zion_config end
        \\  
        \\  local config_path = vim.fn.expand("~/.config/zion/zion.lua")
        \\  if vim.fn.filereadable(config_path) == 1 then
        \\    zion_config = dofile(config_path)
        \\  else
        \\    zion_config = {}
        \\  end
        \\  
        \\  return zion_config
        \\end
        \\
        \\-- Execute zion command asynchronously
        \\local function exec_zion(args, callback)
        \\  local cmd = {"zion"}
        \\  vim.list_extend(cmd, args)
        \\  
        \\  vim.fn.jobstart(cmd, {
        \\    stdout_buffered = true,
        \\    stderr_buffered = true,
        \\    on_exit = function(_, code)
        \\      callback(code == 0)
        \\    end,
        \\    on_stdout = function(_, data)
        \\      if callback then
        \\        callback(true, table.concat(data, "\n"))
        \\      end
        \\    end,
        \\    on_stderr = function(_, data)
        \\      if callback then
        \\        callback(false, table.concat(data, "\n"))
        \\      end
        \\    end,
        \\  })
        \\end
        \\
        \\-- Resolve package name using shortcuts
        \\local function resolve_package_name(name)
        \\  local config = load_config()
        \\  
        \\  -- Check shortcuts first
        \\  if config.shortcuts and config.shortcuts[name] then
        \\    return config.shortcuts[name]
        \\  end
        \\  
        \\  -- If already has slash, return as-is
        \\  if string.find(name, "/") then
        \\    return name
        \\  end
        \\  
        \\  -- Try to resolve with username/org
        \\  if config.github_username then
        \\    return config.github_username .. "/" .. name
        \\  end
        \\  
        \\  if config.github_orgs and #config.github_orgs > 0 then
        \\    return config.github_orgs[1] .. "/" .. name
        \\  end
        \\  
        \\  return name
        \\end
        \\
        \\-- Add a dependency
        \\function M.add_dependency(package_name, callback)
        \\  local resolved_name = resolve_package_name(package_name)
        \\  
        \\  vim.notify("Adding dependency: " .. resolved_name)
        \\  exec_zion({"add", resolved_name}, function(success, output)
        \\    if success then
        \\      vim.notify("✅ Added " .. resolved_name, vim.log.levels.INFO)
        \\    else
        \\      vim.notify("❌ Failed to add " .. resolved_name .. ": " .. (output or ""), vim.log.levels.ERROR)
        \\    end
        \\    if callback then callback(success, output) end
        \\  end)
        \\end
        \\
        \\-- Remove a dependency
        \\function M.remove_dependency(package_name, callback)
        \\  vim.notify("Removing dependency: " .. package_name)
        \\  exec_zion({"remove", package_name}, function(success, output)
        \\    if success then
        \\      vim.notify("✅ Removed " .. package_name, vim.log.levels.INFO)
        \\    else
        \\      vim.notify("❌ Failed to remove " .. package_name .. ": " .. (output or ""), vim.log.levels.ERROR)
        \\    end
        \\    if callback then callback(success, output) end
        \\  end)
        \\end
        \\
        \\-- List dependencies
        \\function M.list_dependencies(callback)
        \\  exec_zion({"list", "--json"}, function(success, output)
        \\    if success and output then
        \\      local deps = vim.fn.json_decode(output)
        \\      if callback then callback(deps) end
        \\    else
        \\      vim.notify("❌ Failed to list dependencies", vim.log.levels.ERROR)
        \\    end
        \\  end)
        \\end
        \\
        \\-- Check project health
        \\function M.check_project(callback)
        \\  exec_zion({"check"}, function(success, output)
        \\    if success then
        \\      vim.notify("✅ Project check completed", vim.log.levels.INFO)
        \\    else
        \\      vim.notify("⚠️  Project has issues", vim.log.levels.WARN)
        \\    end
        \\    if callback then callback(success, output) end
        \\  end)
        \\end
        \\
        \\-- Update dependencies
        \\function M.update_dependencies(callback)
        \\  vim.notify("Updating dependencies...")
        \\  exec_zion({"update"}, function(success, output)
        \\    if success then
        \\      vim.notify("✅ Dependencies updated", vim.log.levels.INFO)
        \\    else
        \\      vim.notify("❌ Failed to update dependencies", vim.log.levels.ERROR)
        \\    end
        \\    if callback then callback(success, output) end
        \\  end)
        \\end
        \\
        \\-- Switch Zig version
        \\function M.use_zig_version(version, callback)
        \\  vim.notify("Switching to Zig " .. version)
        \\  exec_zion({"zig", "use", version}, function(success, output)
        \\    if success then
        \\      vim.notify("✅ Now using Zig " .. version, vim.log.levels.INFO)
        \\    else
        \\      vim.notify("❌ Failed to switch Zig version", vim.log.levels.ERROR)
        \\    end
        \\    if callback then callback(success, output) end
        \\  end)
        \\end
        \\
        \\-- Show dependency picker
        \\function M.dependency_picker()
        \\  vim.ui.input({prompt = "Package name: "}, function(package_name)
        \\    if package_name and package_name ~= "" then
        \\      M.add_dependency(package_name)
        \\    end
        \\  end)
        \\end
        \\
        \\-- Show Zig version picker
        \\function M.zig_version_picker()
        \\  -- Get installed versions
        \\  exec_zion({"zig", "list"}, function(success, output)
        \\    if success then
        \\      local versions = {}
        \\      for line in output:gmatch("[^\r\n]+") do
        \\        local version = line:match("  [→ ] (.+)")
        \\        if version then
        \\          table.insert(versions, version:gsub(" %(current%)", ""))
        \\        end
        \\      end
        \\      
        \\      vim.ui.select(versions, {
        \\        prompt = "Select Zig version:",
        \\      }, function(choice)
        \\        if choice then
        \\          M.use_zig_version(choice)
        \\        end
        \\      end)
        \\    end
        \\  end)
        \\end
        \\
        \\-- Setup commands
        \\function M.setup(opts)
        \\  opts = opts or {}
        \\  
        \\  -- Create user commands
        \\  vim.api.nvim_create_user_command("ZionAdd", function(args)
        \\    M.add_dependency(args.args)
        \\  end, {nargs = 1})
        \\  
        \\  vim.api.nvim_create_user_command("ZionRemove", function(args)
        \\    M.remove_dependency(args.args)
        \\  end, {nargs = 1})
        \\  
        \\  vim.api.nvim_create_user_command("ZionList", function()
        \\    M.list_dependencies(function(deps)
        \\      print(vim.inspect(deps))
        \\    end)
        \\  end, {})
        \\  
        \\  vim.api.nvim_create_user_command("ZionCheck", function()
        \\    M.check_project()
        \\  end, {})
        \\  
        \\  vim.api.nvim_create_user_command("ZionUpdate", function()
        \\    M.update_dependencies()
        \\  end, {})
        \\  
        \\  vim.api.nvim_create_user_command("ZionPicker", function()
        \\    M.dependency_picker()
        \\  end, {})
        \\  
        \\  vim.api.nvim_create_user_command("ZionZig", function()
        \\    M.zig_version_picker()
        \\  end, {})
        \\  
        \\  -- Setup keymaps if requested
        \\  if opts.keymaps then
        \\    vim.keymap.set("n", "<leader>za", M.dependency_picker, {desc = "Zion: Add dependency"})
        \\    vim.keymap.set("n", "<leader>zl", function() M.list_dependencies() end, {desc = "Zion: List dependencies"})
        \\    vim.keymap.set("n", "<leader>zc", M.check_project, {desc = "Zion: Check project"})
        \\    vim.keymap.set("n", "<leader>zu", M.update_dependencies, {desc = "Zion: Update dependencies"})
        \\    vim.keymap.set("n", "<leader>zz", M.zig_version_picker, {desc = "Zion: Switch Zig version"})
        \\  end
        \\end
        \\
        \\return M
        \\
    ;
    
    // Create the plugin directory
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.config/nvim/lua/zion", .{home_dir});
    defer allocator.free(plugin_dir);
    
    try fs.cwd().makePath(plugin_dir);
    
    // Write the plugin file
    const plugin_path = try std.fmt.allocPrint(allocator, "{s}/init.lua", .{plugin_dir});
    defer allocator.free(plugin_path);
    
    try fs.cwd().writeFile(.{ .sub_path = plugin_path, .data = plugin_content });
    
    std.debug.print("✅ Created Neovim plugin: {s}\n", .{plugin_path});
    std.debug.print("\n💡 Add this to your Neovim config:\n", .{});
    std.debug.print("   require('zion').setup({{ keymaps = true }})\n", .{});
    std.debug.print("\n🚀 Available commands in Neovim:\n", .{});
    std.debug.print("   :ZionAdd <package>      - Add dependency\n", .{});
    std.debug.print("   :ZionRemove <package>   - Remove dependency\n", .{});
    std.debug.print("   :ZionList               - List dependencies\n", .{});
    std.debug.print("   :ZionCheck              - Check project health\n", .{});
    std.debug.print("   :ZionUpdate             - Update dependencies\n", .{});
    std.debug.print("   :ZionPicker             - Interactive dependency picker\n", .{});
    std.debug.print("   :ZionZig                - Interactive Zig version picker\n", .{});
    std.debug.print("\n⌨️  Default keymaps (if enabled):\n", .{});
    std.debug.print("   <leader>za              - Add dependency\n", .{});
    std.debug.print("   <leader>zl              - List dependencies\n", .{});
    std.debug.print("   <leader>zc              - Check project\n", .{});
    std.debug.print("   <leader>zu              - Update dependencies\n", .{});
    std.debug.print("   <leader>zz              - Switch Zig version\n", .{});
}