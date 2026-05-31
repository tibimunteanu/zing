//========================================================================
// Time unit tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

static void test_timer_frequency_and_value(void)
{
    const uint64_t frequency = glfwGetTimerFrequency();
    const uint64_t first = glfwGetTimerValue();
    const uint64_t second = glfwGetTimerValue();

    EXPECT_TRUE(frequency > 0);
    EXPECT_TRUE(second >= first);
}

static void test_time_set_get_and_monotonicity(void)
{
    glfwSetTime(12.5);
    const double first = glfwGetTime();
    const double second = glfwGetTime();

    EXPECT_TRUE(first >= 12.5);
    EXPECT_TRUE(second >= first);

    glfwSetTime(0.0);
    EXPECT_TRUE(glfwGetTime() >= 0.0);
}

static void test_time_rejects_invalid_values(void)
{
    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetTime(-1.0);
    end_expected_error();

    begin_expected_error(GLFW_INVALID_VALUE);
    glfwSetTime(18446744074.0);
    end_expected_error();
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_timer_frequency_and_value);
    RUN_TEST(test_time_set_get_and_monotonicity);
    RUN_TEST(test_time_rejects_invalid_values);

    return finish_glfw_test();
}
