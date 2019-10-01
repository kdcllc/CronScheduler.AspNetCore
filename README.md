# CronScheduler.AspNetCore

[![Build status](https://ci.appveyor.com/api/projects/status/wrme1wr6kgjp3a0o?svg=true)](https://ci.appveyor.com/project/kdcllc/cronscheduler-aspnetcore)
[![NuGet](https://img.shields.io/nuget/v/CronScheduler.AspNetCore.svg)](https://www.nuget.org/packages?q=CronScheduler.AspNetCore)
[![MyGet](https://img.shields.io/myget/kdcllc/v/CronScheduler.AspNetCore.svg?label=myget)](https://www.myget.org/F/kdcllc/api/v2)

The goal of this library was to design a simple Cron Scheduling engine that is based on build-in Asp.Net Core  IHostedService interface.
It is much lighter than Quartz schedular and operates inside of any .NET Core GenericHost thus makes it simpler to setup and configure.
In addition `IStartupJob` was added to support async initialization before the IWebHost is ready to start. Sample project includes support for
making sure that Database is created before the application starts.

*** Please refer to [Migration notes from 1.x to 2.x](./Migration1x-2x.md) version the library. ***

## Install package for `AspNetCore` hosting .NET CLI

```bash
    dotnet add package CronScheduler.AspNetCore
```

## Install package for `IHost` hosting .NET CLI

```bash
    dotnet add package CronScheduler.Extensions
```

## Uses Crontab format for Jobs/Tasks schedules

This library supports up to 5 seconds job intervals in the Crontab format thank to [HangfireIO/Cronos](https://github.com/HangfireIO/Cronos) library.

You can use [https://crontab-generator.org/](https://crontab-generator.org/) to generated needed job/task schedule.

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


## Examples

### CronSchedulerWorker

This example demonstrates how to use CronScheduler with new Microsoft .NET Core Workers Template
[CronSchedulerWorker](./src/CronSchedulerWorker/README.md)

### CronSchedulerApp

The sample website provides with use-case scenario for this library.

## Singleton dependencies for `ScheduledJob`

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

Then register this service within the `Startup.cs`

```csharp
    services.AddScheduler(builder =>
    {
        builder.Services.AddSingleton<TorahVerses>();

        // Build a policy that will handle exceptions, 408s, and 500s from the remote server
        builder.Services.AddHttpClient<TorahService>()
            .AddTransientHttpErrorPolicy(p => p.RetryAsync());
        builder.AddJob<TorahQuoteJob, TorahQuoteJobOptions>();

        builder.UnobservedTaskExceptionHandler = UnobservedHandler;
    });
```

## Scoped or Transient Dependencies for `ScheduledJob`

```csharp
    public class UserJob : ScheduledJob
    {
        private readonly UserJobOptions _options;
        private readonly IServiceProvider _provider;

        public UserJob(
            IServiceProvider provider,
            IOptionsMonitor<UserJobOptions> options) : base(options.CurrentValue)
        {
            _options = options.CurrentValue;
            _provider = provider ?? throw new ArgumentNullException(nameof(provider));
        }

        public override async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            using (var scope = _provider.CreateScope())
            {
                var userService = scope.ServiceProvider.GetRequiredService<UserService>();

                var users = userService.GetUsers();

                foreach (var user in users)
                {
                    await userService.AddClaimAsync(user, new Claim(_options.ClaimName, DateTime.UtcNow.ToString()));
                }
            }
        }
    }
```

Then register this service within the `Startup.cs`

```csharp
        services.AddScheduler(builder =>
        {
            builder.Services.AddScoped<UserService>();
            builder.AddJob<UserJob, UserJobOptions>();

            builder.UnobservedTaskExceptionHandler = UnobservedHandler;
        });
```

- Sample uses Microsoft.Extensions.Http.Polly extension library to make http calls every 10 seconds.

## `IStartupJobs` to assist with async jobs initialization before the application starts

There are many case scenarios to use StartupJobs for the IWebHost interface or IGenericHost. Most common case scenario is to make sure that database is created and updated.
This library makes it possible by simply doing the following:

- In the Program.cs file add the following:

```csharp
        public static async Task Main(string[] args)
        {
            var host = CreateWebHostBuilder(args).Build();

            // process any async jobs required to get the site up and running
            await host.RunStartupJobsAync();

            host.Run();
        }
```

- Register the startup job in `Program.cs` or in `Startup.cs` file.

```csharp
public static IWebHostBuilder CreateWebHostBuilder(string[] args)
{
    return WebHost.CreateDefaultBuilder(args)
            .ConfigureServices(services =>
            {
                services.AddStartupJob<SeedDatabaseJob>();
            })
            .ConfigureLogging((context, logger) =>
            {
                logger.AddConsole();
                logger.AddDebug();
                logger.AddConfiguration(context.Configuration.GetSection("Logging"));
            })
            .UseStartup<Startup>();
}
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

## Special Thanks to

- [Maarten Balliauw](https://blog.maartenballiauw.be/post/2017/08/01/building-a-scheduled-cache-updater-in-aspnet-core-2.html) for the Asp.Net Core idea for the background hosted implementation.
- [3 ways to use HTTPClientFactory in ASP.NET Core 2.1](http://www.talkingdotnet.com/3-ways-to-use-httpclientfactory-in-asp-net-core-2-1/)

## Docker build

Utilizes [King David Consulting LLC DotNet Docker Image](https://github.com/kdcllc/docker/tree/master/dotnet)

```bash
    docker-compose -f "docker-compose.yml" -f "docker-compose.override.yml" up -d --build
```

### Note

Workaround for  `Retrying 'FindPackagesByIdAsync' for source` in Docker containers restore.

```bash
 dotnet restore --disable-parallel
```

## License

[MIT License Copyright (c) 2017 King David Consulting LLC](./LICENSE)
