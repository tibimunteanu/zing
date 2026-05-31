//========================================================================
// Shared helpers for GLFW C tests
//========================================================================

#ifndef GLFW_TEST_COMMON_H
#define GLFW_TEST_COMMON_H

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <stdio.h>
#include <stdlib.h>

static int failures;
static int expected_error;
static int expected_error_seen;

#define EXPECT_TRUE(expr) expect_true((expr), #expr, __FILE__, __LINE__)
#define EXPECT_EQ_INT(actual, expected) expect_eq_int((actual), (expected), #actual, #expected, __FILE__, __LINE__)
#define EXPECT_NOT_NULL(expr) EXPECT_TRUE((expr) != NULL)
#define EXPECT_NULL(expr) EXPECT_TRUE((expr) == NULL)
#define RUN_TEST(fn) run_test((fn), #fn)

static void expect_true(int value, const char* expr, const char* file, int line)
{
    if (value)
        return;

    fprintf(stderr, "%s:%d: expected true: %s\n", file, line, expr);
    failures++;
}

static void expect_eq_int(int actual,
                          int expected,
                          const char* actual_expr,
                          const char* expected_expr,
                          const char* file,
                          int line)
{
    if (actual == expected)
        return;

    fprintf(stderr,
            "%s:%d: expected %s == %s, got %d and %d\n",
            file,
            line,
            actual_expr,
            expected_expr,
            actual,
            expected);
    failures++;
}

static void error_callback(int error, const char* description)
{
    if (expected_error && error == expected_error)
    {
        expected_error_seen = GLFW_TRUE;
        return;
    }

    fprintf(stderr, "unexpected GLFW error %d: %s\n", error, description);
    failures++;
}

static void begin_expected_error(int error)
{
    expected_error = error;
    expected_error_seen = GLFW_FALSE;
}

static void end_expected_error(void)
{
    EXPECT_TRUE(expected_error_seen);
    expected_error = 0;
    expected_error_seen = GLFW_FALSE;
}

static void reset_no_api_window_hints(void)
{
    glfwDefaultWindowHints();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
}

static GLFWwindow* create_hidden_window(int width, int height, const char* title)
{
    reset_no_api_window_hints();

    GLFWwindow* window = glfwCreateWindow(width, height, title, NULL, NULL);
    EXPECT_NOT_NULL(window);
    return window;
}

static void drain_events(void)
{
    for (int i = 0; i < 4; i++)
        glfwPollEvents();
}

static void run_test(void (*test)(void), const char* name)
{
    const int before = failures;
    test();

    if (failures == before)
        printf("PASS %s\n", name);
    else
        printf("FAIL %s\n", name);
}

static int init_glfw_test(void)
{
    glfwSetErrorCallback(error_callback);
    return glfwInit();
}

static int finish_glfw_test(void)
{
    glfwTerminate();
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}

#endif
