pub fn pumpEvents(_: f64) void {}

pub fn postKey(_: *anyopaque, _: i32, _: bool, _: u8) bool {
    return false;
}

pub fn postMouseMove(_: *anyopaque, _: f64, _: f64) bool {
    return false;
}

pub fn postMouseButton(_: *anyopaque, _: i32, _: bool, _: f64, _: f64, _: u8) bool {
    return false;
}

pub fn postScroll(_: *anyopaque, _: f64, _: f64) bool {
    return false;
}
