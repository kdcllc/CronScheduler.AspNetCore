# Migration Guide

This document provide with direction for migration between different version of the library.

## Migration from 3.x to 4.x

- New `net10.0` target. Library target frameworks are now `net10.0` and `netstandard2.0`.
- Prerelease builds are published to nuget.org. Install them with `dotnet add package CronScheduler.Extensions --prerelease` and remove any custom prerelease package source from `NuGet.config`.
- **Target frameworks are now `net10.0` and `netstandard2.0`.** `net8.0` was removed because .NET 8 (and 9) reach end of support on 2026-11-10. Apps still on .NET 8/9 resolve the `netstandard2.0` build of CronScheduler.Extensions and should move to .NET 10.
- **CronScheduler.AspNetCore contains no API on net10.0** (its only type is the `IWebHost` extension). On .NET 10 reference **CronScheduler.Extensions directly**; CronScheduler.AspNetCore still references it transitively, so existing references keep working.
- **Breaking on net10.0:** `RunStartupJobsAsync(this IWebHost)` (CronScheduler.AspNetCore) is not available on net10.0 because `IWebHost` is obsolete. Call `RunStartupJobsAsync()` on `IHost`/`WebApplication` (CronScheduler.Extensions `StartupJobHostExtensions`). The `netstandard2.0` build keeps the `IWebHost` overload.
- The sample app's `Microsoft.Extensions.Http.Polly` was replaced by `Microsoft.Extensions.Http.Resilience` (`AddStandardResilienceHandler()`).
- All Microsoft.Extensions dependencies are 10.0.x on every target.
- `CronJitterSeed` is opt-in: the default `null` means no jitter and existing schedules are unchanged; an `H` schedule requires a seed.

### Cronos 0.13.0

CronScheduler now uses Cronos 0.13.0 instead of 0.8.x. Existing five-field and six-field expressions remain compatible. The upgrade adds:

- Deterministic schedule jitter using `H` and the optional `SchedulerOptions.CronJitterSeed` property.
- Cron macros such as `@hourly` and `@daily`, including jittered macro schedules when a seed is configured.
- Reverse schedule inspection through `SchedulerTaskWrapper.GetPreviousOccurrence`.
- Cronos fixes from versions 0.9 through 0.13, including nullable annotations, strong-named assemblies, expanded date ranges, and occurrence edge-case corrections.

To adopt jitter, add a stable integer seed and use `H` in the expression:

```json
{
  "CronSchedule": "H H * * * *",
  "CronJitterSeed": 1207
}
```

No configuration change is required for existing schedules. Do not use `H` without a seed; Cronos rejects that configuration.

## Migration from 2.x to 3.x version

- `ScheduledJob` class is removed from the library.

2.x job code:

```csharp
    public class TorahQuoteJob : ScheduledJob
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
            TorahVerses torahVerses) : base(options.CurrentValue)
        {
            _options = options.CurrentValue;
            _service = service ?? throw new ArgumentNullException(nameof(service));
            _torahVerses = torahVerses ?? throw new ArgumentNullException(nameof(torahVerses));
        }

        public override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            _torahVerses.Current = await _service.GetVersesAsync(exp, cancellationToken);
        }
    }
```

Now with 3.x job code:

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

- `IScheduledJob` properties were removed `CronSchedule`, `CronTimeZone`, `RunImmediately`

```csharp
     /// <summary>
    /// Forces the implementation of the required methods for the job.
    /// </summary>
    public interface IScheduledJob
    {
        /// <summary>
        /// The name of the executing job.
        /// In order for the <see cref="SchedulerOptions"/> options to work correctly make sure that the name is matched
        /// between the job and the named job options.
        /// </summary>
        string Name { get; }

        /// <summary>
        /// Job that will be executing on this schedule.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task ExecuteAsync(CancellationToken cancellationToken);
    }
```

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

## Migration from 1.x to 2.x version

Version 2.0 introduced new package that supports generic `IHost` and doesn't have dependencies on `AspNetCore`.

## Packages changes

- `CronScheduler.Extensions` contains the basic generic code for Cron Scheduler.
- `CronScheduler.AspNetCore` contains specific extensions for `AspNetCore` hosting.

## Namespaces Changed

- `using CronScheduler.AspNetCore;` to `using CronScheduler.Extensions.Scheduler;`

- `using CronScheduler.AspNetCore;` to `using CronScheduler.Extensions.StartupInitializer`
