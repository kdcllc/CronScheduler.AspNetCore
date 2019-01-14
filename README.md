# CronScheduler.AspNetCore 
[![Build status](https://ci.appveyor.com/api/projects/status/wrme1wr6kgjp3a0o?svg=true)](https://ci.appveyor.com/project/kdcllc/cronscheduler-aspnetcore)

The goal of this library was to utilize IHostedService interface for Asp.Net Core 2.1 for scheduled jobs/tasks.
It is lighter than Quartz schedular and operates inside of any GenericHost.

## Uses Crontab format for Jobs/Tasks schedules
This library does not include implementations for seconds in the Crontab format.
You can use [https://crontab-generator.org/](https://crontab-generator.org/) to generated needed job/task schedule.
The following crontab format is supported:

```
*    *    *    *    *  
┬    ┬    ┬    ┬    ┬
│    │    │    │    │
│    │    │    │    │
│    │    │    │    └───── day of week (0 - 6) (Sunday=0 )
│    │    │    └────────── month (1 - 12)
│    │    └─────────────── day of month (1 - 31)
│    └──────────────────── hour (0 - 23)
└───────────────────────── min (0 - 59)
```

```txt
  `* * * * *`        Every minute.
  `0 * * * *`        Top of every hour.
  `0,1,2 * * * *`    Every hour at minutes 0, 1, and 2.
  `*/2 * * * *`      Every two minutes.
  `1-55 * * * *`     Every minute through the 55th minute.
  `* 1,10,20 * * *`  Every 1st, 10th, and 20th hours.
```
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
- [NCrontab](https://github.com/atifaziz/NCrontab)
- [3 ways to use HTTPClientFactory in ASP.NET Core 2.1](http://www.talkingdotnet.com/3-ways-to-use-httpclientfactory-in-asp-net-core-2-1/)

## Docker build
Utilizes [King David Consulting LLC DotNet Docker Image](https://github.com/kdcllc/docker/tree/master/dotnet)

```bash

    docker-compose -f "docker-compose.yml" -f "docker-compose.override.yml" up -d --build
```
