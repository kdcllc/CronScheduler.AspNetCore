
Change Log
===============================================================================

Version 1.5.0 (2018-03-12)
----------------------------
 * Resolved issue#1 "Add option to not run job on application start"
 * Resolved issue#2 "Add option to disable job"
 * Add new Extension method that allows adding of the depended jobs:
    ```c#
        services.AddScheduler(builder =>
        {
            // recommended to use TryAddSingleton
            builder.Services.TryAddSingleton<IScheduledJob, TorahQuoteJob>();
            builder.UnobservedTaskExceptionHandler = UnobservedHandler;
        });
    ```
 * Add functional tests.

Version 1.4.0
----------------------------
 * Intial design
