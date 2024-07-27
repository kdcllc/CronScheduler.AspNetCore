# CronScheduler.AspNetCore

![master workflow](https://github.com/github/docs/actions/workflows/master.yml/badge.svg)
[![NuGet](https://img.shields.io/nuget/v/CronScheduler.AspNetCore.svg)](https://www.nuget.org/packages?q=CronScheduler.AspNetCore)
![Nuget](https://img.shields.io/nuget/dt/CronScheduler.AspNetCore)
[![feedz.io](https://img.shields.io/badge/endpoint.svg?url=https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/shield/CronScheduler.AspNetCore/latest)](https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/packages/CronScheduler.AspNetCore/latest/download)

*Note: Pre-release packages are distributed via [feedz.io](https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/nuget/index.json).*

![I Stand With Israel](./img/IStandWithIsrael.png)

## Summary

**Unlock the Power of Simplified Cron Scheduling in Your .NET Core Apps**

Are you tired of complex scheduling libraries holding you back from building scalable and efficient applications? Look no further! Introducing **CronScheduler**, a lightweight and easy-to-use library designed specifically for .NET Core `IHost` or `IWebHost`.

Built with the KISS principle in mind, CronScheduler is a simplified alternative to Quartz Scheduler and its alternatives. With CronScheduler, you can easily schedule tasks using cron syntax and operate within any .NET Core GenericHost `IHost`, making setup and configuration a breeze.

But that's not all! We've also introduced **IStartupJob**, allowing for async initialization of critical processes before the host is ready to start. This means you can ensure your application is properly initialized and running smoothly, even in complex Kubernetes environments.

**Benefits:**

* Lightweight and easy-to-use library
* Simplified scheduling with cron syntax
* Operates within .NET Core GenericHost `IHost` or `IWebHost`
* Async initialization support for critical processes with IStartupJob

**Join the CronScheduler community today and start simplifying your application's scheduling needs!**

>
> **Please refer to [Migration Guide](./Migration.md) for the upgrade.**
>
[![buymeacoffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/vyve0og)

## Give a Star! :star:

If you like or are using this project to learn or start your solution, please give it a star. Thanks!

## Installation

- Install package for `AspNetCore` hosting .NET CLI

```bash
    dotnet add package CronScheduler.AspNetCore
```

- Install package for `IHost` hosting .NET CLI

```bash
    dotnet add package CronScheduler.Extensions
```

## Uses Crontab format for Jobs/Tasks schedules

This library supports up to 5 seconds job intervals in the Crontab format thank to [HangfireIO/Cronos](https://github.com/HangfireIO/Cronos) library.

You can use [https://crontab-generator.org/](https://crontab-generator.org/) to generated needed job/task schedule.

### Cron format

Cron expression is a mask to define fixed times, dates and intervals. The mask consists of second (optional), minute, hour, day-of-month, month and day-of-week fields. All of the fields allow you to specify multiple values, and any given date/time will satisfy the specified Cron expression, if all the fields contain a matching value.

                                           Allowed values    Allowed special characters   Comment

    ┌───────────── second (optional)       0-59              * , - /                      
    │ ┌───────────── minute                0-59              * , - /                      
    │ │ ┌───────────── hour                0-23              * , - /                      
    │ │ │ ┌───────────── day of month      1-31              * , - / L W ?                
    │ │ │ │ ┌───────────── month           1-12 or JAN-DEC   * , - /                      
    │ │ │ │ │ ┌───────────── day of week   0-6  or SUN-SAT   * , - / # L ?                Both 0 and 7 means SUN
    │ │ │ │ │ │
    * * * * * *

## Demo Applications

- [CronSchedulerWorker](./src/CronSchedulerWorker/) - this example demonstrates how to use `CronScheduler` with new Microsoft .NET Core Workers Template
- [CronSchedulerApp](./src/CronSchedulerApp) - this example demonstrates how to use `CronScheduler` with AspNetCore applications.

There are two ways that options and jobs can be registered within the Scheduler Jobs.

1. The basic and most effective way to register is via `IConfiguration`

This job registration is assuming that the name of the job and options name are the same.

```csharp
    services.AddScheduler(ctx =>
    {
        ctx.AddJob<TestJob>();
    });
```

2. The complex factory registration of the same cron job with different options

```csharp
        services.AddScheduler(ctx =>
        {
            var jobName1 = "TestJob1";

            ctx.AddJob(
                sp =>
                {
                    var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(jobName1);
                    return new TestJobDup(options, mockLoggerTestJob.Object);
                },
                options =>
                {
                    options.CronSchedule = "*/5 * * * * *";
                    options.RunImmediately = true;
                },
                jobName: jobName1);

            var jobName2 = "TestJob2";

            ctx.AddJob(
                sp =>
                {
                    var options = sp.GetRequiredService<IOptionsMonitor<SchedulerOptions>>().Get(jobName2);
                    return new TestJobDup(options, mockLoggerTestJob.Object);
                }, options =>
                {
                    options.CronSchedule = "*/5 * * * * *";
                    options.RunImmediately = true;
                },
                jobName: jobName2);
        });
```

## Sample code for Singleton Schedule Job and its dependencies

```csharp
    public class TorahQuoteJob : IScheduledJob
    {
        private readonly TorahQuoteJobOptions _options;
        private readonly TorahVerses _torahVerses;
        private readonly TorahService _service;

        /// <summary>
        /// Initializes a new instance of the <see cref="TorahQuoteJob"/> class.
        /// </summary>
        /// <param name="options"></param>
        /// <param name="service"></param>
        /// <param name="torahVerses"></param>
        public TorahQuoteJob(
            IOptionsMonitor<TorahQuoteJobOptions> options,
            TorahService service,
            TorahVerses torahVerses)
        {
            _options = options.Get(Name);
            _service = service ?? throw new ArgumentNullException(nameof(service));
            _torahVerses = torahVerses ?? throw new ArgumentNullException(nameof(torahVerses));
        }

        // job name and options name must match.
        public string Name { get; } = nameof(TorahQuoteJob);

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            _torahVerses.Current = await _service.GetVersesAsync(exp, cancellationToken);
        }
    }
```

Then register this service within the `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddScheduler(builder =>
{
    builder.Services.AddSingleton<TorahVerses>();
    builder.Services
        .AddHttpClient<TorahService>()
        .AddTransientHttpErrorPolicy(p => p.RetryAsync());

    builder.AddJob<TorahQuoteJob, TorahQuoteJobOptions>();
    builder.Services.AddScoped<UserService>();
    builder.AddJob<UserJob, UserJobOptions>();

    builder.AddUnobservedTaskExceptionHandler(sp =>
    {
        var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger("CronJobs");
        return (sender, args) =>
        {
            logger?.LogError(args.Exception?.Message);
            args.SetObserved();
        };
    });
});

builder.Services.AddBackgroundQueuedService(applicationOnStopWaitForTasksToComplete: true);
builder.Services.AddDatabaseDeveloperPageExceptionFilter();

builder.Services.AddStartupJob<SeedDatabaseStartupJob>();
builder.Services.AddStartupJob<TestStartupJob>();

builder.Logging.AddConsole();
builder.Logging.AddDebug();
builder.Logging.AddConfiguration(builder.Configuration.GetSection("Logging"));

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseMigrationsEndPoint();
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseCookiePolicy();
app.UseAuthentication();
app.UseRouting();

app.MapControllers();
app.MapDefaultControllerRoute();
app.MapRazorPages();

await app.RunStartupJobsAsync();
await app.RunAsync();
```


## `IStartupJobs` to assist with async jobs initialization before the application starts

There are many case scenarios to use StartupJobs for the `IWebHost` interface or `IGenericHost`. The most common case scenario is to make sure that the database is created and updated.
This library makes it possible by simply doing the following:

- In the `Program.cs` file add the following:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddStartupJob<SeedDatabaseStartupJob>();
builder.Services.AddStartupJob<TestStartupJob>();

var app = builder.Build();

// Configure the HTTP request pipeline.
await app.RunStartupJobsAsync();
await app.RunAsync();
```
## Background Queues

In some instances of the application the need for queuing of the tasks is required. In order to enable this add the following in `Startup.cs`.

```csharp
    services.AddBackgroundQueuedService();
```

Then add sample async task to be executed by the Queued Hosted Service.

```csharp

    public class MyService
    {
        private readonly IBackgroundTaskQueue _taskQueue;

        public MyService(IBackgroundTaskQueue taskQueue)
        {
            _taskQueue = taskQueue;
        }

        public void RunTask()
        {
            _taskQueue.QueueBackgroundWorkItem(async (token)=>
            {
                // run some task
                await Task.Delay(TimeSpan.FromSeconds(10), token);
            }});
        }
    }
```

## License

[MIT License](./LICENSE)
