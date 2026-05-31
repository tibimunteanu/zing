//========================================================================
// Cursor unit tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

#include <float.h>

static int cursor_pos_callback_count;
static int cursor_enter_callback_count;

static void cursor_pos_callback(GLFWwindow* window, double xpos, double ypos)
{
    (void) window;
    (void) xpos;
    (void) ypos;
    cursor_pos_callback_count++;
}

static void cursor_enter_callback(GLFWwindow* window, int entered)
{
    (void) window;
    (void) entered;
    cursor_enter_callback_count++;
}

static void test_cursor_position_queries(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "cursor-position");
    if (!window)
        return;

    double xpos = -1.0;
    double ypos = -1.0;
    glfwGetCursorPos(window, &xpos, &ypos);
    EXPECT_TRUE(xpos > -DBL_MAX && xpos < DBL_MAX);
    EXPECT_TRUE(ypos > -DBL_MAX && ypos < DBL_MAX);

    glfwGetCursorPos(window, NULL, &ypos);
    EXPECT_TRUE(ypos > -DBL_MAX && ypos < DBL_MAX);
    glfwGetCursorPos(window, &xpos, NULL);
    EXPECT_TRUE(xpos > -DBL_MAX && xpos < DBL_MAX);

    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetCursorPos(window, -1.0 / 0.0, 0.0);
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_cursor_creation_and_assignment(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "cursor-create");
    if (!window)
        return;

    unsigned char pixels[16] =
    {
        255, 255, 255, 255,
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255
    };
    GLFWimage image = { 2, 2, pixels };
    GLFWcursor* cursor = glfwCreateCursor(&image, 0, 0);
    EXPECT_NOT_NULL(cursor);
    if (cursor)
    {
        glfwSetCursor(window, cursor);
        glfwSetCursor(window, NULL);
        glfwDestroyCursor(cursor);
    }

    GLFWimage invalid = { 0, 2, pixels };
    begin_expected_error(GLFW_INVALID_VALUE);
    EXPECT_NULL(glfwCreateCursor(&invalid, 0, 0));
    end_expected_error();

    glfwDestroyCursor(NULL);
    glfwDestroyWindow(window);
}

static void test_standard_cursors(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "standard-cursors");
    if (!window)
        return;

    const int shapes[] =
    {
        GLFW_ARROW_CURSOR,
        GLFW_IBEAM_CURSOR,
        GLFW_CROSSHAIR_CURSOR,
        GLFW_POINTING_HAND_CURSOR,
        GLFW_RESIZE_EW_CURSOR,
        GLFW_RESIZE_NS_CURSOR,
        GLFW_RESIZE_NWSE_CURSOR,
        GLFW_RESIZE_NESW_CURSOR,
        GLFW_RESIZE_ALL_CURSOR,
        GLFW_NOT_ALLOWED_CURSOR
    };

    for (int i = 0; i < (int) (sizeof(shapes) / sizeof(shapes[0])); i++)
    {
        GLFWcursor* cursor = glfwCreateStandardCursor(shapes[i]);
        EXPECT_NOT_NULL(cursor);
        if (cursor)
        {
            glfwSetCursor(window, cursor);
            glfwDestroyCursor(cursor);
        }
    }

    begin_expected_error(GLFW_INVALID_ENUM);
    EXPECT_NULL(glfwCreateStandardCursor(0x7fffffff));
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_cursor_input_modes(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "cursor-modes");
    if (!window)
        return;

    EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_CURSOR), GLFW_CURSOR_NORMAL);

    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_CURSOR), GLFW_CURSOR_HIDDEN);
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_CURSOR), GLFW_CURSOR_NORMAL);
#ifdef __APPLE__
    begin_expected_error(GLFW_FEATURE_UNIMPLEMENTED);
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_CAPTURED);
    end_expected_error();
#else
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_CAPTURED);
    EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_CURSOR), GLFW_CURSOR_CAPTURED);
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
#endif

    EXPECT_TRUE(glfwRawMouseMotionSupported() == GLFW_TRUE ||
                glfwRawMouseMotionSupported() == GLFW_FALSE);

    if (glfwRawMouseMotionSupported())
    {
        glfwSetInputMode(window, GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);
        EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_RAW_MOUSE_MOTION), GLFW_TRUE);
        glfwSetInputMode(window, GLFW_RAW_MOUSE_MOTION, GLFW_FALSE);
        EXPECT_EQ_INT(glfwGetInputMode(window, GLFW_RAW_MOUSE_MOTION), GLFW_FALSE);
    }
    else
    {
        begin_expected_error(GLFW_PLATFORM_ERROR);
        glfwSetInputMode(window, GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);
        end_expected_error();
    }

    begin_expected_error(GLFW_INVALID_ENUM);
    glfwGetInputMode(window, 0x7fffffff);
    end_expected_error();

    begin_expected_error(GLFW_INVALID_ENUM);
    glfwSetInputMode(window, GLFW_CURSOR, 0x7fffffff);
    end_expected_error();

    glfwDestroyWindow(window);
}

static void test_cursor_callback_registration(void)
{
    GLFWwindow* window = create_hidden_window(320, 240, "cursor-callbacks");
    if (!window)
        return;

    EXPECT_TRUE(glfwSetCursorPosCallback(window, cursor_pos_callback) == NULL);
    EXPECT_TRUE(glfwSetCursorPosCallback(window, NULL) == cursor_pos_callback);
    EXPECT_TRUE(glfwSetCursorEnterCallback(window, cursor_enter_callback) == NULL);
    EXPECT_TRUE(glfwSetCursorEnterCallback(window, NULL) == cursor_enter_callback);

    EXPECT_EQ_INT(cursor_pos_callback_count, 0);
    EXPECT_EQ_INT(cursor_enter_callback_count, 0);

    glfwDestroyWindow(window);
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_cursor_position_queries);
    RUN_TEST(test_cursor_creation_and_assignment);
    RUN_TEST(test_standard_cursors);
    RUN_TEST(test_cursor_input_modes);
    RUN_TEST(test_cursor_callback_registration);

    return finish_glfw_test();
}
