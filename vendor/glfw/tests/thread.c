//========================================================================
// Thread-facing event tests for the Vulkan-only GLFW fork
//========================================================================

#include "test_common.h"

#if defined(_WIN32)
 #include <windows.h>
#else
 #include <pthread.h>
 #include <time.h>
#endif

struct worker_state
{
    int posted;
};

#if defined(_WIN32)
static DWORD WINAPI post_empty_event_thread(LPVOID data)
{
    struct worker_state* state = data;
    Sleep(50);
    state->posted = GLFW_TRUE;
    glfwPostEmptyEvent();
    return 0;
}
#else
static void* post_empty_event_thread(void* data)
{
    struct worker_state* state = data;
    struct timespec delay = { 0, 50 * 1000 * 1000 };
    nanosleep(&delay, NULL);
    state->posted = GLFW_TRUE;
    glfwPostEmptyEvent();
    return NULL;
}
#endif

static void test_post_empty_event_from_worker_thread(void)
{
    struct worker_state state = { 0 };
    const double start = glfwGetTime();

#if defined(_WIN32)
    HANDLE thread = CreateThread(NULL, 0, post_empty_event_thread, &state, 0, NULL);
    EXPECT_NOT_NULL(thread);
    if (!thread)
        return;
#else
    pthread_t thread;
    EXPECT_EQ_INT(pthread_create(&thread, NULL, post_empty_event_thread, &state), 0);
#endif

    glfwWaitEventsTimeout(1.0);
    const double elapsed = glfwGetTime() - start;

    EXPECT_EQ_INT(state.posted, GLFW_TRUE);
    EXPECT_TRUE(elapsed < 1.0);

#if defined(_WIN32)
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
#else
    pthread_join(thread, NULL);
#endif
}

static void test_wait_events_timeout_validation(void)
{
    const double start = glfwGetTime();
    glfwWaitEventsTimeout(0.001);
    EXPECT_TRUE(glfwGetTime() >= start);
}

int main(void)
{
    if (!init_glfw_test())
        return EXIT_FAILURE;

    RUN_TEST(test_post_empty_event_from_worker_thread);
    RUN_TEST(test_wait_events_timeout_validation);

    return finish_glfw_test();
}
