# CronSchedulerApp

![master workflow](https://github.com/github/docs/actions/workflows/master.yml/badge.svg)
[![NuGet](https://img.shields.io/nuget/v/CronScheduler.AspNetCore.svg)](https://www.nuget.org/packages?q=CronScheduler.AspNetCore)
![Nuget](https://img.shields.io/nuget/dt/CronScheduler.AspNetCore)
[![feedz.io](https://img.shields.io/badge/endpoint.svg?url=https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/shield/CronScheduler.AspNetCore/latest)](https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/packages/CronScheduler.AspNetCore/latest/download)

*Note: Pre-release packages are distributed via [feedz.io](https://f.feedz.io/kdcllc/cronscheduler-aspnetcore/nuget/index.json).*

This ASP.NET Core web application demonstrates various scheduled jobs and how to use them. It includes examples of background tasks, startup jobs, and scheduled jobs using the CronScheduler library.

![I Stand With Israel](../../img/IStandWithIsrael.png)

[![buymeacoffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/vyve0og)

## Give a Star! :star:

If you like or are using this project to learn or start your solution, please give it a star. Thanks!

## Using Scheduled Jobs in ASP.NET Core Web Application

This application demonstrates how to use scheduled jobs in an ASP.NET Core web application. The application leverages the CronScheduler library to manage and execute scheduled tasks. Below are the steps to add and configure scheduled jobs:

### Job Details

#### SeedDatabaseStartupJob

This job demonstrates how to use EF context to seed the database before any request is served. It ensures that the database exists and creates 5 users.

#### UserJob

This job demonstrates how to add a claim to each user in the database. It retrieves users from the database and adds a claim with the current UTC time.

#### TestJob

This job is a simple test job that logs its execution. It will be removed in the next release.

#### TorahQuoteJob

This job retrieves a random verse from the Torah and updates the current verses in the `TorahVerses` service.

### Adding a Scheduled Job

1. **Create a Job Class**: Implement the `IScheduledJob` interface in your job class. For example:

    ```csharp
    using System;
    using System.Threading;
    using System.Threading.Tasks;
    using CronScheduler.Extensions.Scheduler;
    using Microsoft.Extensions.Logging;

    public class MyScheduledJob : IScheduledJob
    {
        private readonly ILogger<MyScheduledJob> _logger;

        public MyScheduledJob(ILogger<MyScheduledJob> logger)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public string Name { get; } = nameof(MyScheduledJob);

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("Executing scheduled job: {jobName}", Name);
            // Your job logic here
            await Task.CompletedTask;
        }
    }
    ```

2. **Configure Job Options**: Create a class that inherits from `SchedulerOptions` to define job-specific options.

    ```csharp
    using CronScheduler.Extensions.Scheduler;

    public class MyScheduledJobOptions : SchedulerOptions
    {
        public string SomeOption { get; set; } = string.Empty;
    }
    ```

3. **Register the Job**: In your `Program.cs` or `Startup.cs`, register the job and its options with the scheduler. Additionally, add a custom error processing for internal errors using an unobserved task exception handler.

    ```csharp
    services.AddScheduler(builder =>
    {
        builder.AddJob<MyScheduledJob, MyScheduledJobOptions>();
    });

    // Add a custom error processing for internal errors
    builder.AddUnobservedTaskExceptionHandler(sp =>
    {
        var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger("CronJobs");
        return (sender, args) =>
        {
            logger?.LogError(args.Exception?.Message);
            args.SetObserved();
        };
    });
    ```

### Adding Jobs on the Fly

Jobs can also be added on the fly and configured from a database class where the options are stored using the following syntax:

```csharp
var jobOptions = await _dbContext.JobOptions.FindAsync("TestJob");
_schedulerRegistration.AddOrUpdate(new TestJob(jobOptions, _loggerFactory.CreateLogger<TestJob>()), jobOptions);
```

### Sample Job Options

Below are sample options for configuring the jobs in the `appsettings.json` file:

```json
{
  "SchedulerJobs": {
    "TorahQuoteJob": {
      "RunImmediately": true,
      "ApiUrl": "http://labs.bible.org/api/",
      "WebsiteUrl": "https://studybible.info/KJV_Strongs",
      "CronSchedule": "0/10 * * * * *",
      "Verses": [
        "Genesis 1:1-3",
        "Exodus 3:14-15",
        "Isaiah 53",
        "Isaiah 26:18",
        "Proverbs 14:23",
        "Daniel 12:1-12"
      ]
    },
    "UserJob": {
      "RunImmediately": true,
      "CronSchedule": "2 9 * * *",
      "ClaimName": "TestClaim"
    }
  }
}
```

### Running the Application

#### Docker Container

1. **Build the Docker Image**: Use the following command to build the Docker image.

    ```bash
    docker build --pull --rm -f "src/CronSchedulerApp/Dockerfile" -t cronscheduler:latest .
    ```

2. **Run the Docker Container**: Use the following command to run the Docker container.

    ```bash
    docker run --rm -d -p 4443:443/tcp -p 8080:80/tcp cronscheduler:latest
    ```

#### Run `dotnet`

1. **Build and Run**: Build and run your application using the following commands. The scheduled jobs will be executed based on their configured schedules.

    ```bash
    # Navigate to the project directory
    cd src/CronSchedulerApp

    # Build the project
    dotnet build

    # Run the project
    dotnet run
    ```
