Exploring raylib and zig with hotreloading and build.zig. `raylib-c`
contains source files of raylib with small modification of
`raylib-c/src/build.zig` to export shared library instead of static
one. There is also the option of using build.zig.zon by:
1. `zig fetch --save=raylib
   https://github.com/raysan5/raylib/archive/<hash>.tar.gz` and
   replace with appropriate hash
2. add the following to `build.zig`:

``` zig
const raylib_dep = b.dependency("raylib", .{
    .target = target,
    .optimize = optimize,
});
exe.linkLibrary(raylib_dep.artifact("raylib"));
```

