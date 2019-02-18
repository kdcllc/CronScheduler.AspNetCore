using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class QueuedHostedService : BackgroundService
    {
        private readonly ILogger<QueuedHostedService> _logger;

        public QueuedHostedService(
            IBackgroundTaskQueue taskQueued,
            ILoggerFactory loggerFactory)
        {
            TaskQueued = taskQueued;
            _logger = loggerFactory.CreateLogger<QueuedHostedService>();
        }

        public IBackgroundTaskQueue TaskQueued { get; }

        public override Task StartAsync(CancellationToken cancellationToken)
        {
            _logger.LogDebug($"{nameof(QueuedHostedService)} is starting.");

            return base.StartAsync(cancellationToken);
        }

        public override Task StopAsync(CancellationToken cancellationToken)
        {
            _logger.LogDebug($"{nameof(QueuedHostedService)} is stopping.");
            return base.StopAsync(cancellationToken);
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var (workItem, workItemName, onException) =  await TaskQueued.DequeueAsync(stoppingToken);

                try
                {
                    await workItem(stoppingToken);
                }
                catch (Exception ex)
                {
                    var message = $"Error occured executing {workItemName}";

                    onException(new Exception(message, ex));

                    _logger.LogError(ex, message);
                }
            }
        }
    }
}
