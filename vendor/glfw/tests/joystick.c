//========================================================================
// Joystick unit tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

#include <string.h>

static int joystick_callback_count;

static void joystick_callback(int jid, int event)
{
    EXPECT_TRUE(jid >= GLFW_JOYSTICK_1);
    EXPECT_TRUE(jid <= GLFW_JOYSTICK_LAST);
    EXPECT_TRUE(event == GLFW_CONNECTED || event == GLFW_DISCONNECTED);
    joystick_callback_count++;
}

static void test_joystick_callback_registration(void)
{
    EXPECT_TRUE(glfwSetJoystickCallback(joystick_callback) == NULL);
    EXPECT_TRUE(glfwSetJoystickCallback(NULL) == joystick_callback);
    EXPECT_EQ_INT(joystick_callback_count, 0);
}

static void test_joystick_queries(void)
{
    int connected_count = 0;

    for (int jid = GLFW_JOYSTICK_1; jid <= GLFW_JOYSTICK_LAST; jid++)
    {
        int axis_count = -1;
        int button_count = -1;
        int hat_count = -1;
        int marker = jid + 100;

        const int present = glfwJoystickPresent(jid);
        EXPECT_TRUE(present == GLFW_TRUE || present == GLFW_FALSE);

        const float* axes = glfwGetJoystickAxes(jid, &axis_count);
        const unsigned char* buttons = glfwGetJoystickButtons(jid, &button_count);
        const unsigned char* hats = glfwGetJoystickHats(jid, &hat_count);
        const char* name = glfwGetJoystickName(jid);
        const char* guid = glfwGetJoystickGUID(jid);

        if (present)
        {
            connected_count++;
            EXPECT_TRUE(axis_count >= 0);
            EXPECT_TRUE(button_count >= 0);
            EXPECT_TRUE(hat_count >= 0);
            EXPECT_NOT_NULL(name);
            EXPECT_NOT_NULL(guid);
            if (axis_count > 0)
                EXPECT_NOT_NULL(axes);
            if (button_count > 0)
                EXPECT_NOT_NULL(buttons);
            if (hat_count > 0)
                EXPECT_NOT_NULL(hats);

            glfwSetJoystickUserPointer(jid, &marker);
            EXPECT_TRUE(glfwGetJoystickUserPointer(jid) == &marker);

            const int is_gamepad = glfwJoystickIsGamepad(jid);
            EXPECT_TRUE(is_gamepad == GLFW_TRUE || is_gamepad == GLFW_FALSE);

            if (is_gamepad)
            {
                GLFWgamepadstate state;
                EXPECT_NOT_NULL(glfwGetGamepadName(jid));
                EXPECT_EQ_INT(glfwGetGamepadState(jid, &state), GLFW_TRUE);
            }
            else
            {
                GLFWgamepadstate state;
                EXPECT_NULL(glfwGetGamepadName(jid));
                EXPECT_EQ_INT(glfwGetGamepadState(jid, &state), GLFW_FALSE);
            }
        }
        else
        {
            EXPECT_EQ_INT(axis_count, 0);
            EXPECT_EQ_INT(button_count, 0);
            EXPECT_EQ_INT(hat_count, 0);
            EXPECT_NULL(axes);
            EXPECT_NULL(buttons);
            EXPECT_NULL(hats);
            EXPECT_NULL(name);
            EXPECT_NULL(guid);
            EXPECT_NULL(glfwGetJoystickUserPointer(jid));
            EXPECT_EQ_INT(glfwJoystickIsGamepad(jid), GLFW_FALSE);
            EXPECT_NULL(glfwGetGamepadName(jid));
            GLFWgamepadstate state;
            EXPECT_EQ_INT(glfwGetGamepadState(jid, &state), GLFW_FALSE);
        }
    }

    EXPECT_TRUE(connected_count >= 0);
}

static void test_gamepad_mapping_update(void)
{
    const char* mapping =
        "030000005e0400008e02000000000000,Test Controller,"
        "a:b0,b:b1,x:b2,y:b3,back:b4,start:b6,guide:b8,"
        "leftshoulder:b9,rightshoulder:b10,leftstick:b11,rightstick:b12,"
        "dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,"
        "leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5\n";

    EXPECT_EQ_INT(glfwUpdateGamepadMappings(mapping), GLFW_TRUE);
    EXPECT_EQ_INT(glfwUpdateGamepadMappings("# comment only\n"), GLFW_TRUE);
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_joystick_callback_registration);
    RUN_TEST(test_joystick_queries);
    RUN_TEST(test_gamepad_mapping_update);

    return finish_glfw_test();
}
