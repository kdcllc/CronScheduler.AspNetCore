# Migration Guide

This document provide with direction for migration between different version of the library.

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
