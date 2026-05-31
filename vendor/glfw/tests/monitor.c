//========================================================================
// Monitor unit tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

#include <string.h>

static int monitor_callback_count;

static void monitor_callback(GLFWmonitor* monitor, int event)
{
    EXPECT_NOT_NULL(monitor);
    EXPECT_TRUE(event == GLFW_CONNECTED || event == GLFW_DISCONNECTED);
    monitor_callback_count++;
}

static GLFWmonitor* primary_monitor(void)
{
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();
    EXPECT_NOT_NULL(monitor);
    return monitor;
}

static void test_monitor_enumeration(void)
{
    int count = 0;
    GLFWmonitor** monitors = glfwGetMonitors(&count);

    EXPECT_NOT_NULL(monitors);
    EXPECT_TRUE(count > 0);
    EXPECT_TRUE(glfwGetPrimaryMonitor() == monitors[0]);

    for (int i = 0; i < count; i++)
        EXPECT_NOT_NULL(monitors[i]);
}

static void test_monitor_geometry_and_scale(void)
{
    GLFWmonitor* monitor = primary_monitor();
    if (!monitor)
        return;

    int xpos = 1;
    int ypos = 1;
    int work_x = 1;
    int work_y = 1;
    int work_width = 0;
    int work_height = 0;
    int width_mm = 0;
    int height_mm = 0;
    float xscale = 0.f;
    float yscale = 0.f;

    glfwGetMonitorPos(monitor, &xpos, &ypos);
    glfwGetMonitorWorkarea(monitor, &work_x, &work_y, &work_width, &work_height);
    glfwGetMonitorPhysicalSize(monitor, &width_mm, &height_mm);
    glfwGetMonitorContentScale(monitor, &xscale, &yscale);

    EXPECT_TRUE(work_width > 0);
    EXPECT_TRUE(work_height > 0);
    EXPECT_TRUE(width_mm > 0);
    EXPECT_TRUE(height_mm > 0);
    EXPECT_TRUE(xscale > 0.f);
    EXPECT_TRUE(yscale > 0.f);

    glfwGetMonitorPos(monitor, NULL, &ypos);
    glfwGetMonitorWorkarea(monitor, NULL, NULL, &work_width, NULL);
    glfwGetMonitorPhysicalSize(monitor, &width_mm, NULL);
    glfwGetMonitorContentScale(monitor, NULL, &yscale);

    EXPECT_TRUE(work_width > 0);
    EXPECT_TRUE(width_mm > 0);
    EXPECT_TRUE(yscale > 0.f);
    (void) xpos;
    (void) ypos;
    (void) work_x;
    (void) work_y;
}

static void test_monitor_name_and_user_pointer(void)
{
    int marker = 7;
    GLFWmonitor* monitor = primary_monitor();
    if (!monitor)
        return;

    const char* name = glfwGetMonitorName(monitor);
    EXPECT_NOT_NULL(name);
    EXPECT_TRUE(strlen(name) > 0);

    EXPECT_NULL(glfwGetMonitorUserPointer(monitor));
    glfwSetMonitorUserPointer(monitor, &marker);
    EXPECT_TRUE(glfwGetMonitorUserPointer(monitor) == &marker);
    glfwSetMonitorUserPointer(monitor, NULL);
    EXPECT_NULL(glfwGetMonitorUserPointer(monitor));
}

static void test_video_modes(void)
{
    GLFWmonitor* monitor = primary_monitor();
    if (!monitor)
        return;

    int count = 0;
    const GLFWvidmode* modes = glfwGetVideoModes(monitor, &count);
    const GLFWvidmode* current = glfwGetVideoMode(monitor);

    EXPECT_NOT_NULL(modes);
    EXPECT_NOT_NULL(current);
    EXPECT_TRUE(count > 0);
    EXPECT_TRUE(current->width > 0);
    EXPECT_TRUE(current->height > 0);
    EXPECT_TRUE(current->redBits > 0);
    EXPECT_TRUE(current->greenBits > 0);
    EXPECT_TRUE(current->blueBits > 0);

    for (int i = 0; i < count; i++)
    {
        EXPECT_TRUE(modes[i].width > 0);
        EXPECT_TRUE(modes[i].height > 0);
        EXPECT_TRUE(modes[i].redBits > 0);
        EXPECT_TRUE(modes[i].greenBits > 0);
        EXPECT_TRUE(modes[i].blueBits > 0);
    }
}

static void test_gamma_ramp_roundtrip(void)
{
    GLFWmonitor* monitor = primary_monitor();
    if (!monitor)
        return;

    const GLFWgammaramp* ramp = glfwGetGammaRamp(monitor);
    EXPECT_NOT_NULL(ramp);
    if (!ramp)
        return;

    EXPECT_TRUE(ramp->size > 0);
    EXPECT_NOT_NULL(ramp->red);
    EXPECT_NOT_NULL(ramp->green);
    EXPECT_NOT_NULL(ramp->blue);

    glfwSetGammaRamp(monitor, ramp);
}

static void test_monitor_callback_registration(void)
{
    EXPECT_TRUE(glfwSetMonitorCallback(monitor_callback) == NULL);
    EXPECT_TRUE(glfwSetMonitorCallback(NULL) == monitor_callback);
    EXPECT_EQ_INT(monitor_callback_count, 0);
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_monitor_enumeration);
    RUN_TEST(test_monitor_geometry_and_scale);
    RUN_TEST(test_monitor_name_and_user_pointer);
    RUN_TEST(test_video_modes);
    RUN_TEST(test_gamma_ramp_roundtrip);
    RUN_TEST(test_monitor_callback_registration);

    return finish_glfw_test();
}
