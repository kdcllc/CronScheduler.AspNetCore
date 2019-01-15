# CronScheduler.AspNetCore 
[![Build status](https://ci.appveyor.com/api/projects/status/wrme1wr6kgjp3a0o?svg=true)](https://ci.appveyor.com/project/kdcllc/cronscheduler-aspnetcore)

The goal of this library was to utilize IHostedService interface for Asp.Net Core 2.1 for scheduled jobs/tasks.
It is lighter than Quartz schedular and operates inside of any GenericHost.

## Uses Crontab format for Jobs/Tasks schedules
This library does not include implementations for seconds in the Crontab format.
You can use [https://crontab-generator.org/](https://crontab-generator.org/) to generated needed job/task schedule.
The following crontab format is supported:

- [Now Supports HangfireIO/Cronos](https://github.com/HangfireIO/Cronos)

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

## Example CronSchedulerApp
The sample website provides with use-case scenario for this library.

Includes the following sample service:
```c#
 public class TorahQuoteJob : IScheduledJob
    {
        public string CronSchedule { get; }

        private readonly TorahService _service;
        private readonly TorahSettings _options;

        public TorahQuoteJob(IOptions<TorahSettings> options, TorahService service)
        {
            _options = options.Value;
            CronSchedule = _options.CronSchedule; //set to 1 min in appsettings.json "* * * * *"
            _service = service;
        }
        

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            var result = await _service.GetVerses(exp, cancellationToken);

            TorahVerses.Current = result;
        }
    }
```

Then register this service within the `Startup.cs`
```c#
    services.AddScheduler(builder =>
    {
        // recommended to use TryAddSingleton
        builder.Services.TryAddSingleton<IScheduledJob, TorahQuoteJob>();
        builder.UnobservedTaskExceptionHandler = UnobservedHandler;
    });
```
- Sample uses Microsoft.Extensions.Http.Polly extension library to make http calls every minute.

## Special Thanks to
- [Maarten Balliauw](https://blog.maartenballiauw.be/post/2017/08/01/building-a-scheduled-cache-updater-in-aspnet-core-2.html) for the Asp.Net Core idea for the background hosted implementation.
- [3 ways to use HTTPClientFactory in ASP.NET Core 2.1](http://www.talkingdotnet.com/3-ways-to-use-httpclientfactory-in-asp-net-core-2-1/)

## Docker build
Utilizes [King David Consulting LLC DotNet Docker Image](https://github.com/kdcllc/docker/tree/master/dotnet)

```bash
    docker-compose -f "docker-compose.yml" -f "docker-compose.override.yml" up -d --build
```
