const std = @import("std");
const zsync = @import("zsync");

/// Zeke HTTP client for Zion integration
/// Provides access to Zeke's AI-powered project analysis and package recommendations
pub const ZekeClient = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    base_url: []const u8,
    http_client: std.http.Client,
    
    const Self = @This();
    
    /// Initialize Zeke client with default localhost configuration
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .base_url = "http://localhost:8080",
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }
    
    /// Initialize Zeke client with custom URL
    pub fn initWithUrl(allocator: std.mem.Allocator, io: zsync.Io, base_url: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .base_url = base_url,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.http_client.deinit(allocator);
    }
    
    /// Project analysis response structure
    pub const ProjectAnalysis = struct {
        project_info: ProjectInfo,
        dependencies: []DependencyInfo,
        build_issues: []BuildIssue,
        summary: ProjectSummary,
        
        pub const ProjectInfo = struct {
            name: []const u8,
            build_system: []const u8,
            module_count: u32,
            optimization_level: []const u8,
        };
        
        pub const DependencyInfo = struct {
            name: []const u8,
            version: []const u8,
            security_score: u8,
            registry: []const u8,
            alternatives: [][]const u8,
        };
        
        pub const BuildIssue = struct {
            type: []const u8,
            severity: []const u8,
            message: []const u8,
            suggestion: []const u8,
            file: []const u8,
            line: u32,
        };
        
        pub const ProjectSummary = struct {
            health_score: u8,
            readiness: []const u8,
            recommendations: [][]const u8,
        };
    };
    
    /// Package recommendation response structure
    pub const PackageRecommendation = struct {
        query: []const u8,
        total_found: u32,
        search_time_ms: u32,
        recommendations: []PackageInfo,
        
        pub const PackageInfo = struct {
            name: []const u8,
            score: f32,
            reason: []const u8,
            registry: []const u8,
            version: []const u8,
            alternatives: []Alternative,
            
            pub const Alternative = struct {
                name: []const u8,
                reason: []const u8,
                score: f32,
            };
        };
    };
    
    /// Dependency suggestion response structure
    pub const DependencySuggestion = struct {
        query: []const u8,
        suggestions: []SuggestionInfo,
        
        pub const SuggestionInfo = struct {
            name: []const u8,
            description: []const u8,
            security_score: u8,
            popularity_score: u8,
            maintenance_score: u8,
            registry: []const u8,
            latest_version: []const u8,
        };
    };
    
    /// Analyze current project using Zeke's project analysis API
    pub fn analyzeProject(self: *Self, project_path: []const u8) !ProjectAnalysis {
        const payload = try std.fmt.allocPrint(self.allocator, 
            "{{\"path\": \"{s}\"}}", .{project_path});
        defer self.allocator.free(payload);
        
        const response = try self.makeRequest("POST", "/api/project_analyze", payload);
        defer self.allocator.free(response);
        
        return try self.parseProjectAnalysis(response);
    }
    
    /// Get AI-powered package recommendations
    pub fn recommendPackages(self: *Self, need: []const u8) !PackageRecommendation {
        const payload = try std.fmt.allocPrint(self.allocator, 
            "{{\"need\": \"{s}\"}}", .{need});
        defer self.allocator.free(payload);
        
        const response = try self.makeRequest("POST", "/api/package_recommend", payload);
        defer self.allocator.free(response);
        
        return try self.parsePackageRecommendation(response);
    }
    
    /// Get dependency suggestions based on query
    pub fn suggestDependencies(self: *Self, query: []const u8) !DependencySuggestion {
        const payload = try std.fmt.allocPrint(self.allocator, 
            "{{\"query\": \"{s}\"}}", .{query});
        defer self.allocator.free(payload);
        
        const response = try self.makeRequest("POST", "/api/dependency_suggest", payload);
        defer self.allocator.free(response);
        
        return try self.parseDependencySuggestion(response);
    }
    
    /// Chat with Zeke's AI for general assistance
    pub fn chat(self: *Self, message: []const u8) ![]const u8 {
        const payload = try std.fmt.allocPrint(self.allocator, 
            "{{\"message\": \"{s}\"}}", .{message});
        defer self.allocator.free(payload);
        
        const response = try self.makeRequest("POST", "/api/chat", payload);
        return response; // Caller owns the memory
    }
    
    /// Check if Zeke server is running and accessible
    pub fn healthCheck(self: *Self) bool {
        const response = self.makeRequest("GET", "/health", "") catch return false;
        defer self.allocator.free(response);
        return true;
    }
    
    /// Make HTTP request to Zeke server
    fn makeRequest(self: *Self, method: []const u8, endpoint: []const u8, payload: []const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, endpoint });
        defer self.allocator.free(url);
        
        const uri = try std.Uri.parse(url);
        
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit(allocator);
        
        try headers.append("Content-Type", "application/json");
        try headers.append("Accept", "application/json");
        
        var request = try self.http_client.open(.GET, uri, headers, .{});
        defer request.deinit(allocator);
        
        if (std.mem.eql(u8, method, "POST")) {
            request.transfer_encoding = .{ .content_length = payload.len };
            try request.send();
            try request.writeAll(payload);
        } else {
            try request.send();
        }
        
        try request.finish();
        try request.wait();
        
        if (request.response.status != .ok) {
            return error.ZekeServerError;
        }
        
        const response_body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024); // 1MB max
        return response_body;
    }
    
    /// Parse project analysis JSON response
    fn parseProjectAnalysis(self: *Self, json_str: []const u8) !ProjectAnalysis {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch |err| {
            std.debug.print("Failed to parse project analysis JSON: {}\n", .{err});
            return error.InvalidJsonResponse;
        };
        defer parsed.deinit(allocator);
        
        // TODO: Implement proper JSON parsing for ProjectAnalysis
        // For now, return a basic structure
        return ProjectAnalysis{
            .project_info = .{
                .name = "unknown",
                .build_system = "zig",
                .module_count = 0,
                .optimization_level = "Debug",
            },
            .dependencies = &[_]ProjectAnalysis.DependencyInfo{},
            .build_issues = &[_]ProjectAnalysis.BuildIssue{},
            .summary = .{
                .health_score = 75,
                .readiness = "development",
                .recommendations = &[_][]const u8{},
            },
        };
    }
    
    /// Parse package recommendation JSON response  
    fn parsePackageRecommendation(self: *Self, json_str: []const u8) !PackageRecommendation {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch |err| {
            std.debug.print("Failed to parse package recommendation JSON: {}\n", .{err});
            return error.InvalidJsonResponse;
        };
        defer parsed.deinit(allocator);
        
        // TODO: Implement proper JSON parsing for PackageRecommendation
        // For now, return a basic structure
        return PackageRecommendation{
            .query = "unknown",
            .total_found = 0,
            .search_time_ms = 0,
            .recommendations = &[_]PackageRecommendation.PackageInfo{},
        };
    }
    
    /// Parse dependency suggestion JSON response
    fn parseDependencySuggestion(self: *Self, json_str: []const u8) !DependencySuggestion {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch |err| {
            std.debug.print("Failed to parse dependency suggestion JSON: {}\n", .{err});
            return error.InvalidJsonResponse;
        };
        defer parsed.deinit(allocator);
        
        // TODO: Implement proper JSON parsing for DependencySuggestion
        // For now, return a basic structure
        return DependencySuggestion{
            .query = "unknown",
            .suggestions = &[_]DependencySuggestion.SuggestionInfo{},
        };
    }
};