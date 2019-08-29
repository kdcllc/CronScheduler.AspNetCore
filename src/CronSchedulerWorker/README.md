# CronScheduler with .NET Core Workers Template

This sample application demonstrate utilization of new .NET Core Worker template and CronScheduler.AspNetCore.

## Hosting in Azure Container

[.NET Core Workers in Azure Container Instances](https://devblogs.microsoft.com/aspnet/dotnet-core-workers-in-azure-container-instances)

1. Build the Docker Container

```bash
    docker build --rm -f "src\CronSchedulerWorker\Dockerfile" -t cronschedulerworker:latest .
```

2. Run the Docker Container

```bash
    docker run --rm -it cronschedulerworker:latest
```

## Windows Service

[.NET Core Workers as Windows Services](https://devblogs.microsoft.com/aspnet/net-core-workers-as-windows-services/)

## Systemd

[.NET Core and systemd Linux](https://devblogs.microsoft.com/dotnet/net-core-and-systemd/)
