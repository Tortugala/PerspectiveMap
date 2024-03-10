struct Uniforms {
    scroll : vec2<f32>,
    screen_size: vec2<f32>,
    zoom : f32,
    axis: f32,
};

@binding(0) @group(0) var<uniform> ubo : Uniforms;

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
};	

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vertex_main(
    triangle: VertexInput, @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = vec4<f32>(triangle.position, 0.0, 1.0);
    out.color = triangle.color;
    return out;
}

@fragment
fn fragment_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return render_perspective_map(in.clip_position.xy, ubo.screen_size, ubo.zoom, degrees_to_radians(ubo.axis));
}

//===================//
//RENDERING FUNCTIONS//
//===================//

fn render_perspective_map(clip_position_xy: vec2<f32>, max_clip_position: vec2<f32>, zoom: f32, axis: f32) -> vec4<f32> {
    //TODO: Try changing paper size to match zoom to test focal length changes..?
    let paper: vec2<f32> = get_paper_from_clip(clip_position_xy, max_clip_position, degrees_to_radians(180.0));
    var angle = atan2(paper.x, paper.y);
    var distance = get_angle_to_paper(paper, zoom);
    var paper_xyz: vec3<f32> = vec3<f32>(0.0, 0.0, 1.0);
    
    //Rotate to the correct tilt.
    paper_xyz = rotate_vec3_around_x(paper_xyz, distance);
    
    //Rotate to the correct rota.
    paper_xyz = rotate_vec3_around_z(paper_xyz, angle);
    
    //Render base vanishing ring dividers.
    var z = radians_to_degrees(acos(paper_xyz.z));
    var counter = -90.0;
    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    while(counter <= 90.0) {
        var temp_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        if (color.x == 0.0) {
            temp_color = vec4<f32>(0.5, 0.5, 0.5, 1.0);
        }
        if (color.x == 0.5) {
            temp_color = vec4<f32>(1.0, 1.0, 1.0, 1.0);
        }
        if (color.x == 1.0) {
            temp_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        }
        color = temp_color;
        counter += 10.0;
        if !(counter -0.1 <= z && counter + 0.1 >= z) {
            continue;
        }
        return color;
    }
    let base_tan = radians_to_degrees(atan2(paper_xyz.x, paper_xyz.y));
    
    //Render base rotation percentage dividers.
    counter = -180.0;
    while (counter <= 180.0) {
        counter += 45.0;
        if !(counter - 1.0 <= base_tan && counter + 1.0 >= base_tan) {
            continue;
        }
        return vec4<f32>(1.0, 1.0, 1.0, 1.0);
    }
    
    //Align around axis.
    paper_xyz = rotate_vec3_around_y(paper_xyz, axis);
    
    //Render aligned rotation percentage divders.
    let tan = radians_to_degrees(atan2(paper_xyz.x, paper_xyz.y));
    var rotation = 10.0;
    var last_rotation = 0.0;
    counter = -180.0;
    while (counter <= 180.0) {
        counter += 45.0;
        if !(counter - 1.0 <= tan && counter + 1.0 >= tan) {
            continue;
        }
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    
    //Fill aligned vanishing rings.
    rotation = 10.0;
    last_rotation = 0.0;
    color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (paper_xyz.z >= 0.0) {
        while (rotation <= 90) {
            var temp_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            if (color.x == 0.0) {
                temp_color = vec4<f32>(0.5, 0.5, 0.0, 1.0);
            }
            if (color.x == 0.5) {
                temp_color = vec4<f32>(1.0, 0.0, 0.0, 1.0);
            }
            if (color.x == 1.0) {
                temp_color = vec4<f32>(0.0, 1.0, 0.0, 1.0);
            }
            color = temp_color;
            if (paper_xyz.z <= sin(degrees_to_radians(rotation)) && paper_xyz.z >= sin(degrees_to_radians(last_rotation)))   {
                break;
            }
            last_rotation = rotation;
            if (rotation == 80) {
                rotation += 9;
            }
            else if (rotation == 89) {
                rotation += 1;
            }
            else {
                rotation += 10;
            }
        }
    }
    else {
        rotation = -10.0;
        while (rotation >= -90) {
            var temp_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            if (color.x == 0.0) {
                temp_color = vec4<f32>(0.5, 0.5, 0.8, 1.0);
            }
            if (color.x == 0.5) {
                temp_color = vec4<f32>(1.0, 0.0, 0.8, 1.0);
            }
            if (color.x == 1.0) {
                temp_color = vec4<f32>(0.0, 1.0, 0.8, 1.0);
            }
            color = temp_color;
            if (paper_xyz.z <= sin(degrees_to_radians(last_rotation)) && paper_xyz.z >= sin(degrees_to_radians(rotation)))   {
                break;
            }
            last_rotation = rotation;
            if (rotation == -80) {
                rotation -= 9;
            }
            else if (rotation == -89) {
                rotation -= 1;
            }
            else {
                rotation -= 10;
            }
        }
    }
    return color;
}

//==============//
//DATA FUNCTIONS//
//==============//

fn get_paper_from_clip(clip_position_xy: vec2<f32>, max_clip_position: vec2<f32>, paper_size: f32) -> vec2<f32> {
    var square_max_clip_position = max_clip_position;
    if (max_clip_position.x < max_clip_position.y) {
        square_max_clip_position.x = max_clip_position.y;
    }
    else {
        square_max_clip_position.y = max_clip_position.x;
    }
    return range_vec2(clip_position_xy, square_max_clip_position, vec2<f32>(0.0, 0.0), vec2<f32>(paper_size, paper_size), vec2<f32>(paper_size / 2, paper_size / 2));
}

fn get_angle_to_paper(paper: vec2<f32>, zoom: f32) -> f32 {
    let opposite = zoom;
    let adjacent = pythag(paper.x, paper.y);
    let hypotenuse = pythag(opposite, adjacent);
    var angle = 0.0;
    if (adjacent < hypotenuse) {
        angle = asin(adjacent / hypotenuse);
    }
    else {
        angle = asin(hypotenuse / adjacent);
    }
    return angle;
}

//==============//
//MATH FUNCTIONS//
//==============//

fn get_angle_between_vec3(a: vec3<f32>, b: vec3<f32>) -> f32 {
    return acos(dot(a, b)/(mag(a)*mag(b)));
}

fn dot(a: vec3<f32>, b: vec3<f32>) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn mag(a: vec3<f32>) -> f32 {
    return sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

fn pythag(a:f32, b:f32) -> f32 {
    return sqrt((a * a) + (b * b));
}

fn range_vec3(vec: vec3<f32>, old_range: vec3<f32>, old_offset: vec3<f32>, new_range: vec3<f32>, new_offset: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
    range(vec.x, old_range.x, old_offset.x, new_range.x, new_offset.x),
    range(vec.y, old_range.y, old_offset.y, new_range.y, new_offset.y),
    range(vec.z, old_range.z, old_offset.z, new_range.z, new_offset.z)
    );
}

fn range_vec2(vec: vec2<f32>, old_range: vec2<f32>, old_offset: vec2<f32>, new_range: vec2<f32>, new_offset: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
    range(vec.x, old_range.x, old_offset.x, new_range.x, new_offset.x),
    range(vec.y, old_range.y, old_offset.y, new_range.y, new_offset.y)
    );
}

fn range(value: f32, old_range: f32, old_offset: f32, new_range: f32, new_offset: f32) -> f32 {
    return (((value + old_offset) / old_range) * new_range) - new_offset;
}

fn radians_to_degrees(radians: f32) -> f32 {
    return radians * (180 / 3.141592653589793);    
}

fn degrees_to_radians(degrees: f32) -> f32 {
    return degrees * (3.141592653589793 / 180);
}

fn rotate_vec3_around_x(vec: vec3<f32>, radians: f32) -> vec3<f32> {
    var rotated_vec = vec;
    let matrix = array<vec3<f32>,3>(
    vec3<f32>(1, 0, 0),
    vec3<f32>(0, cos(radians), -sin(radians)),
    vec3<f32>(0, sin(radians), cos(radians))
    );
    rotated_vec.x = (vec.x * matrix[0].x) + (vec.y * matrix[0].y) + (vec.z * matrix[0].z);
    rotated_vec.y = (vec.x * matrix[1].x) + (vec.y * matrix[1].y) + (vec.z * matrix[1].z);
    rotated_vec.z = (vec.x * matrix[2].x) + (vec.y * matrix[2].y) + (vec.z * matrix[2].z);
    return rotated_vec;
}

fn rotate_vec3_around_y(vec: vec3<f32>, radians: f32) -> vec3<f32> {
    var rotated_vec = vec;
    let matrix = array<vec3<f32>,3>(
    vec3<f32>(cos(radians), 0, sin(radians)),
    vec3<f32>(0, 1, 0),
    vec3<f32>(-sin(radians), 0, cos(radians))
    );
    rotated_vec.x = (vec.x * matrix[0].x) + (vec.y * matrix[0].y) + (vec.z * matrix[0].z);
    rotated_vec.y = (vec.x * matrix[1].x) + (vec.y * matrix[1].y) + (vec.z * matrix[1].z);
    rotated_vec.z = (vec.x * matrix[2].x) + (vec.y * matrix[2].y) + (vec.z * matrix[2].z);
    return rotated_vec;
}

fn rotate_vec3_around_z(vec: vec3<f32>, radians: f32) -> vec3<f32> {
    var rotated_vec = vec;
    let matrix = array<vec3<f32>,3>(
    vec3<f32>(cos(radians), -sin(radians), 0),
    vec3<f32>(sin(radians), cos(radians), 0),
    vec3<f32>(0, 0, 1)
    );
    rotated_vec.x = (vec.x * matrix[0].x) + (vec.y * matrix[0].y) + (vec.z * matrix[0].z);
    rotated_vec.y = (vec.x * matrix[1].x) + (vec.y * matrix[1].y) + (vec.z * matrix[1].z);
    rotated_vec.z = (vec.x * matrix[2].x) + (vec.y * matrix[2].y) + (vec.z * matrix[2].z);
    return rotated_vec;
}
