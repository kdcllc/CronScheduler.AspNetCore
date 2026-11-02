# CronScheduler.AspNetCore

[![Publish](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/publish.yml/badge.svg?branch=master)](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/publish.yml)
[![PR CI](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/pr.yml/badge.svg)](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/pr.yml)
[![CodeQL](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/codeql.yml/badge.svg)](https://github.com/kdcllc/CronScheduler.AspNetCore/actions/workflows/codeql.yml)
[![CronScheduler.Extensions](https://img.shields.io/nuget/v/CronScheduler.Extensions.svg?label=CronScheduler.Extensions)](https://www.nuget.org/packages/CronScheduler.Extensions)
[![CronScheduler.Extensions preview](https://img.shields.io/nuget/vpre/CronScheduler.Extensions.svg?label=preview)](https://www.nuget.org/packages/CronScheduler.Extensions/absoluteLatest)
[![Downloads](https://img.shields.io/nuget/dt/CronScheduler.Extensions.svg)](https://www.nuget.org/packages/CronScheduler.Extensions)
[![CronScheduler.AspNetCore](https://img.shields.io/nuget/v/CronScheduler.AspNetCore.svg?label=CronScheduler.AspNetCore)](https://www.nuget.org/packages/CronScheduler.AspNetCore)
[![CronScheduler.AspNetCore preview](https://img.shields.io/nuget/vpre/CronScheduler.AspNetCore.svg?label=preview)](https://www.nuget.org/packages/CronScheduler.AspNetCore/absoluteLatest)
[![Downloads](https://img.shields.io/nuget/dt/CronScheduler.AspNetCore.svg)](https://www.nuget.org/packages/CronScheduler.AspNetCore)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/kdcllc/CronScheduler.AspNetCore/blob/master/LICENSE)

*Preview (prerelease) packages are published to nuget.org. Install the latest preview with `dotnet add package CronScheduler.Extensions --prerelease`.*

![I Stand With Israel](https://raw.githubusercontent.com/kdcllc/CronScheduler.AspNetCore/master/img/IStandWithIsrael.png)

## Summary

**Unlock the Power of Simplified Cron Scheduling in Your .NET Core Apps**

Introducing **CronScheduler**, a lightweight and easy-to-use library designed for modern .NET `IHost` applications.

Built with the KISS principle in mind, CronScheduler is a simplified alternative to Quartz Scheduler and its alternatives. With CronScheduler, you can easily schedule tasks using cron syntax and operate within any .NET Core GenericHost `IHost`, making setup and configuration a breeze.

But that's not all! We've also introduced **IStartupJob**, allowing for async initialization of critical processes before the host is ready to start. This means you can ensure your application is properly initialized and running smoothly, even in complex Kubernetes environments.

**Benefits:**

* Lightweight and easy-to-use library
* Simplified scheduling with cron syntax
* Operates within the .NET Generic Host (`IHost`)
* Async initialization support for critical processes with `IStartupJob`
* Deterministic schedule jitter to distribute load across jobs and instances
* Previous-occurrence lookup for schedule inspection and diagnostics

**Join the CronScheduler community today and start simplifying your application's scheduling needs!**

>
> **Please refer to [Migration Guide](https://github.com/kdcllc/CronScheduler.AspNetCore/blob/master/Migration.md) for the upgrade.**
>
[![buymeacoffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/vyve0og)

## Give a Star! :star:

If you like or are using this project to learn or start your solution, please give it a star. Thanks!

## Installation

- Install package for any .NET Generic Host (`IHost`) app, including ASP.NET Core `WebApplication` on .NET 10, with .NET CLI. `app.RunStartupJobsAsync()` comes from this package. Targets: `net10.0` and `netstandard2.0`.

```bash
    dotnet add package CronScheduler.Extensions
```

- Install `CronScheduler.AspNetCore` only if you need the legacy `IWebHost` extension on `netstandard2.0` (for example apps on .NET Framework via the netstandard2.0 build). It contains no API on `net10.0`; see the [Migration Guide](https://github.com/kdcllc/CronScheduler.AspNetCore/blob/master/Migration.md). Targets: `net10.0` and `netstandard2.0`.

```bash
    dotnet add package CronScheduler.AspNetCore
```

## Cron schedules

CronScheduler uses [Cronos 0.13.0](https://github.com/HangfireIO/Cronos) to parse schedules and calculate occurrences. It supports standard five-field expressions, six-field expressions with seconds, macros, time zones, reversed ranges, `L`, `W`, `#`, and deterministic jitter with `H`.

Existing five-field and six-field schedules remain compatible. Use [crontab-generator.org](https://crontab-generator.org/) to generate basic expressions, and consult the [Cronos format reference](https://github.com/HangfireIO/Cronos#cron-format) for extended syntax.

### Cron format

Cron expression is a mask to define fixed times, dates and intervals. The mask consists of second (optional), minute, hour, day-of-month, month and day-of-week fields. All of the fields allow you to specify multiple values, and any given date/time will satisfy the specified Cron expression, if all the fields contain a matching value.

                                           Allowed values    Allowed special characters   Comment

    ┌───────────── second (optional)       0-59              * , - / H
    │ ┌───────────── minute                0-59              * , - / H
    │ │ ┌───────────── hour                0-23              * , - / H
    │ │ │ ┌───────────── day of month      1-31              * , - / H L W ?
    │ │ │ │ ┌───────────── month           1-12 or JAN-DEC   * , - / H
    │ │ │ │ │ ┌───────────── day of week   0-6 or SUN-SAT    * , - / H # L ?              Both 0 and 7 mean SUN
    │ │ │ │ │ │
    * * * * * *

Cronos also supports macros: `@every_second`, `@every_minute`, `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly`, and `@annually`.

### Deterministic schedule jitter

Cronos 0.13.0 supports the `H` character to deterministically distribute execution times. Configure `CronJitterSeed` whenever an expression contains `H`. The same expression and seed always produce the same schedule, making it suitable for spreading load without random behavior on restart.

```json
{
  "SchedulerJobs": {
    "TelemetryJob": {
      "CronSchedule": "H H * * * *",
      "CronJitterSeed": 1207,
      "CronTimeZone": "UTC",
      "RunImmediately": false
    }
  }
}
```

The seed also adds jitter to supported macros. For example, `@hourly` with a seed runs once per hour at deterministic minute and second offsets. Using `H` without `CronJitterSeed` is invalid and Cronos throws `MissingSeedException` during registration.

### Previous occurrences

Cronos 0.13.0 can calculate occurrences in reverse. Registered jobs expose this through `SchedulerTaskWrapper.GetPreviousOccurrence`:

```csharp
var registration = services.GetRequiredService<ISchedulerRegistration>();
var job = registration.Jobs[nameof(TelemetryJob)];
var previousRun = job.GetPreviousOccurrence(DateTimeOffset.UtcNow);
```

The calculation uses the job's configured time zone and does not change scheduler state.

## Demo Applications

- [CronSchedulerWorker](https://github.com/kdcllc/CronScheduler.AspNetCore/tree/master/src/CronSchedulerWorker) - this example demonstrates how to use `CronScheduler` with new Microsoft .NET Core Workers Template
- [CronSchedulerApp](https://github.com/kdcllc/CronScheduler.AspNetCore/tree/master/src/CronSchedulerApp) - this example demonstrates how to use `CronScheduler` with AspNetCore applications.

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
        .AddStandardResilienceHandler();

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

Startup jobs run against the modern `IHost` abstraction. A common use case is ensuring a database is created and migrated before the application begins serving requests.
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

## Running tests and code coverage

```bash
dotnet test --project test/CronScheduler.UnitTest/CronScheduler.UnitTest.csproj -c Release --coverage --coverage-output-format cobertura --coverage-output coverage.cobertura.xml
python3 build/coverage-check.py "TestResults/coverage.cobertura.xml"
```

Pull request CI fails when line coverage of the library assemblies (`CronScheduler.Extensions`; `CronScheduler.AspNetCore` has no code on `net10.0`) drops below 80% and writes the coverage summary to the job page; pass `--min` to [`build/coverage-check.py`](https://github.com/kdcllc/CronScheduler.AspNetCore/blob/master/build/coverage-check.py) to override the threshold locally.

## License

[MIT License](https://github.com/kdcllc/CronScheduler.AspNetCore/blob/master/LICENSE)
