const kern_return_t = c_int;

const mach_timebase_info_data_t = extern struct {
    numer: u32,
    denom: u32,
};

var timebase: mach_timebase_info_data_t = .{
    .numer = 1,
    .denom = 1,
};

pub fn init() bool {
    return mach_timebase_info(&timebase) == 0 and timebase.denom != 0;
}

pub fn deinit() void {}

pub fn getTimerValue() u64 {
    return mach_absolute_time();
}

pub fn getTimerFrequency() u64 {
    return @divFloor(1_000_000_000 * @as(u64, timebase.denom), @as(u64, timebase.numer));
}

extern "c" fn mach_absolute_time() u64;
extern "c" fn mach_timebase_info(info: *mach_timebase_info_data_t) kern_return_t;
