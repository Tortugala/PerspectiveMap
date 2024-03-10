const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;

pub const App = @This();

const UniformBufferObject = struct {
    scroll: @Vector(2, f32),
    screen_size: @Vector(2, f32),
    zoom: f32,
    axis: f32,
};

const gpa = std.heap.GeneralPurposeAllocator(.{}){};

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,
vertexBuffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,
bgl: *gpu.BindGroupLayout,

const Vertex = packed struct {
    pos: @Vector(2, f32),
    col: @Vector(4, f32),
};

const vertices = [_]Vertex{
    .{
        .pos = .{ -1.0, 1.0 },
        .col = .{ 1, 0, 0, 1.0 },
    },
    .{
        .pos = .{ 1.0, 1.0 },
        .col = .{ 0, 1, 0, 1.0 },
    },
    .{
        .pos = .{ 1.0, -1.0 },
        .col = .{ 0, 0, 1, 1.0 },
    },

    .{
        .pos = .{ -1.0, 1.0 },
        .col = .{ 1, 0, 0, 1.0 },
    },
    .{
        .pos = .{ 1.0, -1.0 },
        .col = .{ 0, 0, 1, 1.0 },
    },
    .{
        .pos = .{ -1.0, -1.0 },
        .col = .{ 0.0, 0.0, 0.0, 1 },
    },
};

var zoom: f32 = 1.0;
var zoom_speed: f32 = 0.01;
const max_zoom: f32 = 100.0;
const min_zoom: f32 = 0.0;
var last_zoom: f32 = 0.0;
var scroll: @Vector(2, f32) = @Vector(2, f32){ 0.0, 0.0 };
var scroll_speed: f32 = 10.0;
const max_scroll: f32 = 1000.0;
const min_scroll: f32 = -1000.0;
var screen_size: @Vector(2, f32) = @Vector(2, f32){ 0.0, 0.0 };
var last_screen_size: @Vector(2, f32) = @Vector(2, f32){ 0.0, 0.0 };
var axis: f32 = 0.0;
var last_axis: f32 = 0.0;
const max_axis: f32 = 360.0;
const min_axis: f32 = 0.0;
var axis_speed: f32 = 1.0;
var skip_frame: bool = false;

pub fn init(app: *App) !void {
    std.debug.print("=CONTROLS=\nPress a/s to rotate the axis.\nPress z/x to zoom.\n", .{});
    try core.init(.{});

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    const vertex_buffer_attributes = [_]gpu.VertexAttribute{
        .{
            // Vertex positions
            .shader_location = 0,
            .offset = @offsetOf(Vertex, "pos"),
            .format = .float32x2,
        },
        .{
            // Vertex colors
            .shader_location = 1,
            .offset = @offsetOf(Vertex, "col"),
            .format = .float32x4,
        },
    };

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const vertex = gpu.VertexState.init(.{
        .module = shader_module,
        .entry_point = "vertex_main",
        .buffers = &.{
            gpu.VertexBufferLayout.init(.{
                .array_stride = @sizeOf(Vertex),
                .step_mode = .vertex,
                .attributes = &vertex_buffer_attributes,
            }),
        },
    });
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fragment_main",
        .targets = &.{color_target},
    });

    const bgle_buffer = gpu.BindGroupLayout.Entry.buffer(0, .{ .fragment = true }, .uniform, true, 0);

    const bgl = core.device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .entries = &.{bgle_buffer},
        }),
    );

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bgl};

    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &bind_group_layouts,
    }));

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = vertex,
        .layout = pipeline_layout,
    };
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const triangleVertexBuffer = core.device.createBuffer(&gpu.Buffer.Descriptor{
        .label = "trangleVertexBuffer",
        .usage = .{ .vertex = true },
        .mapped_at_creation = .true,
        .size = vertices.len * @sizeOf(Vertex),
    });
    const vertex_mapped = triangleVertexBuffer.getMappedRange(Vertex, 0, vertices.len);
    std.mem.copyBackwards(Vertex, vertex_mapped.?, vertices[0..]);
    triangleVertexBuffer.unmap();

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = .false,
    });

    const bind_group = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = bgl,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
            },
        }),
    );

    app.* = .{ .title_timer = try core.Timer.start(), .pipeline = pipeline, .vertexBuffer = triangleVertexBuffer, .uniform_buffer = uniform_buffer, .bind_group = bind_group, .bgl = bgl };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    _ = app;
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .key_press => |ev| {
                switch (ev.key) {
                    .escape => return true,
                    else => {},
                }
            },
            else => {},
        }
    }

    if (core.keyPressed(.z)) {
        zoom = std.math.clamp(
            zoom + zoom_speed,
            min_zoom,
            max_zoom,
        );
    }
    if (core.keyPressed(.x)) {
        zoom = std.math.clamp(
            zoom - zoom_speed,
            min_zoom,
            max_zoom,
        );
    }
    if (core.keyPressed(.a)) {
        axis = std.math.clamp(
            axis + axis_speed,
            min_axis,
            max_axis,
        );
        if (axis == 360.0) {
            axis = 0.0;
        }
    }
    if (core.keyPressed(.s)) {
        axis = std.math.clamp(
            axis - axis_speed,
            min_axis,
            max_axis,
        );
        if (axis == 0.0) {
            axis = 360.0;
        }
    }

    //TODO: Normalize inputs for smoother scrolling.
    if (core.keyPressed(.left)) {
        scroll[0] = std.math.clamp(
            scroll[0] - scroll_speed,
            min_scroll,
            max_scroll,
        );
    }
    if (core.keyPressed(.right)) {
        scroll[0] = std.math.clamp(
            scroll[0] + scroll_speed,
            min_scroll,
            max_scroll,
        );
    }
    if (core.keyPressed(.up)) {
        scroll[1] = std.math.clamp(
            scroll[1] - scroll_speed,
            min_scroll,
            max_scroll,
        );
    }
    if (core.keyPressed(.down)) {
        scroll[1] = std.math.clamp(
            scroll[1] + scroll_speed,
            min_scroll,
            max_scroll,
        );
    }

    if (last_axis != axis) {
        std.debug.print("Axis = {d}\n", .{axis});
        last_axis = axis;
        skip_frame = false;
    }
    if (last_zoom != zoom) {
        std.debug.print("Zoom = {d}\n", .{zoom});
        last_zoom = zoom;
        skip_frame = false;
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const texture = core.swap_chain.getCurrentTexture().?;
    screen_size[0] = @floatFromInt(texture.getWidth());
    screen_size[1] = @floatFromInt(texture.getHeight());
    if (last_screen_size[0] != screen_size[0] or last_screen_size[1] != screen_size[1]) {
        last_screen_size = screen_size;
        skip_frame = false;
    }
    if (skip_frame) {
        return false;
    }

    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const ubo = UniformBufferObject{
        .scroll = scroll,
        .screen_size = screen_size,
        .zoom = zoom,
        .axis = axis,
    };

    encoder.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setBindGroup(0, app.bind_group, &.{0});
    pass.setVertexBuffer(0, app.vertexBuffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.draw(vertices.len, vertices.len / 3, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // Update the window title every second.
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Perspective Map [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }
    skip_frame = true;
    return false;
}
