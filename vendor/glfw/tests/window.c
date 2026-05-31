//========================================================================
// Window unit tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

#include <string.h>

static int pos_callback_count;
static int size_callback_count;
static int close_callback_count;
static int refresh_callback_count;
static int focus_callback_count;
static int iconify_callback_count;
static int maximize_callback_count;
static int framebuffer_callback_count;
static int scale_callback_count;

static void reset_window_hints(void)
{
    reset_no_api_window_hints();
}

static void test_create_destroy(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "create_destroy");
    if (!window)
        return;

    int width = 0;
    int height = 0;
    int fb_width = 0;
    int fb_height = 0;

    glfwGetWindowSize(window, &width, &height);
    glfwGetFramebufferSize(window, &fb_width, &fb_height);

    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_CLIENT_API), GLFW_NO_API);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_VISIBLE), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FOCUSED), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_ICONIFIED), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_HOVERED), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_AUTO_ICONIFY), GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_DOUBLEBUFFER), GLFW_TRUE);
    EXPECT_TRUE(glfwGetWindowMonitor(window) == NULL);
    EXPECT_TRUE(width > 0);
    EXPECT_TRUE(height > 0);
    EXPECT_TRUE(fb_width > 0);
    EXPECT_TRUE(fb_height > 0);

    glfwDestroyWindow(window);
}

static void test_creation_hints(void)
{
    glfwDefaultWindowHints();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    glfwWindowHint(GLFW_DECORATED, GLFW_FALSE);
    glfwWindowHint(GLFW_FLOATING, GLFW_TRUE);
    glfwWindowHint(GLFW_FOCUS_ON_SHOW, GLFW_FALSE);
    glfwWindowHint(GLFW_AUTO_ICONIFY, GLFW_FALSE);
    glfwWindowHint(GLFW_MOUSE_PASSTHROUGH, GLFW_TRUE);
    glfwWindowHint(GLFW_POSITION_X, 80);
    glfwWindowHint(GLFW_POSITION_Y, 90);

    GLFWwindow* window = glfwCreateWindow(320, 240, "hints", NULL, NULL);
    EXPECT_TRUE(window != NULL);
    if (!window)
        return;

    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_CLIENT_API), GLFW_NO_API);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_VISIBLE), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_RESIZABLE), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_DECORATED), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FLOATING), GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FOCUS_ON_SHOW), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_AUTO_ICONIFY), GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_MOUSE_PASSTHROUGH), GLFW_TRUE);

    glfwDestroyWindow(window);
}

static void test_should_close_and_user_pointer(void)
{
    int marker = 42;
    GLFWwindow* window = create_hidden_window(320, 240, "state");
    if (!window)
        return;

    EXPECT_EQ_INT(glfwWindowShouldClose(window), GLFW_FALSE);
    glfwSetWindowShouldClose(window, GLFW_TRUE);
    EXPECT_EQ_INT(glfwWindowShouldClose(window), GLFW_TRUE);
    glfwSetWindowShouldClose(window, GLFW_FALSE);
    EXPECT_EQ_INT(glfwWindowShouldClose(window), GLFW_FALSE);

    EXPECT_TRUE(glfwGetWindowUserPointer(window) == NULL);
    glfwSetWindowUserPointer(window, &marker);
    EXPECT_TRUE(glfwGetWindowUserPointer(window) == &marker);

    glfwDestroyWindow(window);
}

static void test_title_and_icon(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "title");
    if (!window)
        return;

    EXPECT_TRUE(strcmp(glfwGetWindowTitle(window), "title") == 0);
    glfwSetWindowTitle(window, "renamed window");
    EXPECT_TRUE(strcmp(glfwGetWindowTitle(window), "renamed window") == 0);

    unsigned char pixels[16] =
    {
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 255
    };
    GLFWimage image = { 2, 2, pixels };
#ifdef __APPLE__
    begin_expected_error(GLFW_FEATURE_UNAVAILABLE);
    glfwSetWindowIcon(window, 1, &image);
    end_expected_error();
    begin_expected_error(GLFW_FEATURE_UNAVAILABLE);
    glfwSetWindowIcon(window, 0, NULL);
    end_expected_error();
#else
    glfwSetWindowIcon(window, 1, &image);
    glfwSetWindowIcon(window, 0, NULL);
#endif

    GLFWimage invalid = { 0, 2, pixels };
    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetWindowIcon(window, 1, &invalid);
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_size_position_and_framebuffer_queries(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "size");
    if (!window)
        return;

    int xpos = 0;
    int ypos = 0;
    glfwSetWindowSize(window, 400, 300);
    glfwSetWindowPos(window, 120, 130);
    drain_events();

    int width = 0;
    int height = 0;
    int fb_width = 0;
    int fb_height = 0;
    int left = -1;
    int top = -1;
    int right = -1;
    int bottom = -1;
    float xscale = 0.f;
    float yscale = 0.f;

    glfwGetWindowPos(window, &xpos, &ypos);
    glfwGetWindowSize(window, &width, &height);
    glfwGetFramebufferSize(window, &fb_width, &fb_height);
    glfwGetWindowFrameSize(window, &left, &top, &right, &bottom);
    glfwGetWindowContentScale(window, &xscale, &yscale);

    EXPECT_EQ_INT(width, 400);
    EXPECT_EQ_INT(height, 300);
    EXPECT_TRUE(fb_width >= width);
    EXPECT_TRUE(fb_height >= height);
    EXPECT_TRUE(left >= 0);
    EXPECT_TRUE(top >= 0);
    EXPECT_TRUE(right >= 0);
    EXPECT_TRUE(bottom >= 0);
    EXPECT_TRUE(xscale > 0.f);
    EXPECT_TRUE(yscale > 0.f);

    glfwGetWindowSize(window, NULL, &height);
    EXPECT_EQ_INT(height, 300);
    glfwGetFramebufferSize(window, &fb_width, NULL);
    EXPECT_TRUE(fb_width >= width);
    glfwGetWindowPos(window, NULL, &ypos);
    (void) xpos;
    (void) ypos;

    glfwDestroyWindow(window);
}

static void test_window_attrib_mutators(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "attributes");
    if (!window)
        return;

    glfwSetWindowAttrib(window, GLFW_RESIZABLE, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_RESIZABLE), GLFW_FALSE);
    glfwSetWindowAttrib(window, GLFW_RESIZABLE, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_RESIZABLE), GLFW_TRUE);

    glfwSetWindowAttrib(window, GLFW_DECORATED, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_DECORATED), GLFW_FALSE);
    glfwSetWindowAttrib(window, GLFW_DECORATED, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_DECORATED), GLFW_TRUE);

    glfwSetWindowAttrib(window, GLFW_FLOATING, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FLOATING), GLFW_TRUE);
    glfwSetWindowAttrib(window, GLFW_FLOATING, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FLOATING), GLFW_FALSE);

    glfwSetWindowAttrib(window, GLFW_FOCUS_ON_SHOW, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FOCUS_ON_SHOW), GLFW_FALSE);
    glfwSetWindowAttrib(window, GLFW_FOCUS_ON_SHOW, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_FOCUS_ON_SHOW), GLFW_TRUE);

    glfwSetWindowAttrib(window, GLFW_AUTO_ICONIFY, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_AUTO_ICONIFY), GLFW_FALSE);
    glfwSetWindowAttrib(window, GLFW_AUTO_ICONIFY, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_AUTO_ICONIFY), GLFW_TRUE);

    glfwSetWindowAttrib(window, GLFW_MOUSE_PASSTHROUGH, GLFW_TRUE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_MOUSE_PASSTHROUGH), GLFW_TRUE);
    glfwSetWindowAttrib(window, GLFW_MOUSE_PASSTHROUGH, GLFW_FALSE);
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_MOUSE_PASSTHROUGH), GLFW_FALSE);

    begin_expected_error(GLFW_INVALID_ENUM);
    glfwGetWindowAttrib(window, GLFW_RED_BITS);
    end_expected_error();

    begin_expected_error(GLFW_INVALID_ENUM);
    glfwSetWindowAttrib(window, GLFW_RED_BITS, GLFW_TRUE);
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_visibility_and_window_state_commands(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "visibility");
    if (!window)
        return;

    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_VISIBLE), GLFW_FALSE);

    glfwShowWindow(window);
    drain_events();
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_VISIBLE), GLFW_TRUE);

    glfwRequestWindowAttention(window);
    glfwFocusWindow(window);
    drain_events();

    glfwIconifyWindow(window);
    drain_events();
    glfwRestoreWindow(window);
    drain_events();
    EXPECT_EQ_INT(glfwGetWindowAttrib(window, GLFW_ICONIFIED), GLFW_FALSE);

    glfwMaximizeWindow(window);
    drain_events();
    glfwRestoreWindow(window);
    drain_events();

    glfwHideWindow(window);
    drain_events();

    glfwDestroyWindow(window);
}

static void test_opacity(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "opacity");
    if (!window)
        return;

    const float initial = glfwGetWindowOpacity(window);
    EXPECT_TRUE(initial >= 0.f);
    EXPECT_TRUE(initial <= 1.f);

    glfwSetWindowOpacity(window, 0.75f);
    const float changed = glfwGetWindowOpacity(window);
    EXPECT_TRUE(changed >= 0.f);
    EXPECT_TRUE(changed <= 1.f);

    glfwSetWindowOpacity(window, 1.f);
    EXPECT_TRUE(glfwGetWindowOpacity(window) >= 0.f);

    glfwDestroyWindow(window);
}

static void test_limits_and_title_are_accepted(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "limits");
    if (!window)
        return;

    glfwSetWindowTitle(window, "renamed window");
    glfwSetWindowSizeLimits(window, 160, 120, 640, 480);
    glfwSetWindowAspectRatio(window, 4, 3);
    glfwSetWindowSizeLimits(window, GLFW_DONT_CARE, GLFW_DONT_CARE, GLFW_DONT_CARE, GLFW_DONT_CARE);
    glfwSetWindowAspectRatio(window, GLFW_DONT_CARE, GLFW_DONT_CARE);

    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetWindowSizeLimits(window, -2, 120, 640, 480);
    end_expected_error();

    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetWindowSizeLimits(window, 320, 240, 160, 120);
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_share_window_is_rejected(void)
{
    GLFWwindow* first = create_hidden_window(320, 240, "first");
    if (!first)
        return;

    reset_window_hints();
    begin_expected_error(GLFW_NO_WINDOW_CONTEXT);
    GLFWwindow* second = glfwCreateWindow(320, 240, "second", NULL, first);
    EXPECT_TRUE(second == NULL);
    end_expected_error();

    glfwDestroyWindow(first);
}

static void test_invalid_window_creation_inputs(void)
{
    reset_window_hints();

    begin_expected_error(GLFW_INVALID_VALUE);
    GLFWwindow* zero_width = glfwCreateWindow(0, 240, "zero_width", NULL, NULL);
    EXPECT_TRUE(zero_width == NULL);
    end_expected_error();

    begin_expected_error(GLFW_API_UNAVAILABLE);
    glfwWindowHint(GLFW_CLIENT_API, 12345);
    end_expected_error();

    begin_expected_error(GLFW_INVALID_ENUM);
    glfwWindowHint(0x7fffffff, 1);
    end_expected_error();
}

static void pos_callback(GLFWwindow* window, int xpos, int ypos)
{
    (void) window;
    (void) xpos;
    (void) ypos;
    pos_callback_count++;
}

static void size_callback(GLFWwindow* window, int width, int height)
{
    (void) window;
    (void) width;
    (void) height;
    size_callback_count++;
}

static void close_callback(GLFWwindow* window)
{
    (void) window;
    close_callback_count++;
}

static void refresh_callback(GLFWwindow* window)
{
    (void) window;
    refresh_callback_count++;
}

static void focus_callback(GLFWwindow* window, int focused)
{
    (void) window;
    (void) focused;
    focus_callback_count++;
}

static void iconify_callback(GLFWwindow* window, int iconified)
{
    (void) window;
    (void) iconified;
    iconify_callback_count++;
}

static void maximize_callback(GLFWwindow* window, int maximized)
{
    (void) window;
    (void) maximized;
    maximize_callback_count++;
}

static void framebuffer_callback(GLFWwindow* window, int width, int height)
{
    (void) window;
    (void) width;
    (void) height;
    framebuffer_callback_count++;
}

static void scale_callback(GLFWwindow* window, float xscale, float yscale)
{
    (void) window;
    (void) xscale;
    (void) yscale;
    scale_callback_count++;
}

static void test_callback_registration(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "callbacks");
    if (!window)
        return;

    EXPECT_TRUE(glfwSetWindowPosCallback(window, pos_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowPosCallback(window, NULL) == pos_callback);
    EXPECT_TRUE(glfwSetWindowSizeCallback(window, size_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowSizeCallback(window, NULL) == size_callback);
    EXPECT_TRUE(glfwSetWindowCloseCallback(window, close_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowCloseCallback(window, NULL) == close_callback);
    EXPECT_TRUE(glfwSetWindowRefreshCallback(window, refresh_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowRefreshCallback(window, NULL) == refresh_callback);
    EXPECT_TRUE(glfwSetWindowFocusCallback(window, focus_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowFocusCallback(window, NULL) == focus_callback);
    EXPECT_TRUE(glfwSetWindowIconifyCallback(window, iconify_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowIconifyCallback(window, NULL) == iconify_callback);
    EXPECT_TRUE(glfwSetWindowMaximizeCallback(window, maximize_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowMaximizeCallback(window, NULL) == maximize_callback);
    EXPECT_TRUE(glfwSetFramebufferSizeCallback(window, framebuffer_callback) == NULL);
    EXPECT_TRUE(glfwSetFramebufferSizeCallback(window, NULL) == framebuffer_callback);
    EXPECT_TRUE(glfwSetWindowContentScaleCallback(window, scale_callback) == NULL);
    EXPECT_TRUE(glfwSetWindowContentScaleCallback(window, NULL) == scale_callback);

    EXPECT_EQ_INT(pos_callback_count, 0);
    EXPECT_EQ_INT(size_callback_count, 0);
    EXPECT_EQ_INT(close_callback_count, 0);
    EXPECT_EQ_INT(refresh_callback_count, 0);
    EXPECT_EQ_INT(focus_callback_count, 0);
    EXPECT_EQ_INT(iconify_callback_count, 0);
    EXPECT_EQ_INT(maximize_callback_count, 0);
    EXPECT_EQ_INT(framebuffer_callback_count, 0);
    EXPECT_EQ_INT(scale_callback_count, 0);

    glfwDestroyWindow(window);
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_create_destroy);
    RUN_TEST(test_creation_hints);
    RUN_TEST(test_should_close_and_user_pointer);
    RUN_TEST(test_title_and_icon);
    RUN_TEST(test_size_position_and_framebuffer_queries);
    RUN_TEST(test_window_attrib_mutators);
    RUN_TEST(test_visibility_and_window_state_commands);
    RUN_TEST(test_opacity);
    RUN_TEST(test_limits_and_title_are_accepted);
    RUN_TEST(test_share_window_is_rejected);
    RUN_TEST(test_invalid_window_creation_inputs);
    RUN_TEST(test_callback_registration);

    return finish_glfw_test();
}
