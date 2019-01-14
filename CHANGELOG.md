
Change Log
===============================================================================

Version 1.0.6 (2018-01-14)
* Resolved issue #5 "Add support for SourceLink", to make use of this feature in Visual Studio.NET please deselect `Enable Just My Code` and select `Enable Source Link support` as shown per this image:
![enable](img/source_link_enable.JPG)

* Resovled issue #6 "Add support for kdcllc Docker image" 

* Resolved issue #4 "Add support for seconds with Cron"

```c#
   public string CronTimeZone { get; };

```

Version 1.0.5 (2018-03-12)
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

Version 1.0.4
----------------------------
 * Intial design
