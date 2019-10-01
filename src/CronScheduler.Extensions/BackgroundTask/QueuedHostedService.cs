using System;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CronScheduler.Extensions.BackgroundTask
{
    public class QueuedHostedService : BackgroundService
    {
        private readonly ILogger<QueuedHostedService> _logger;
        private readonly BackgroundTaskContext _context;

        // https://github.com/aspnet/AspNetCore/issues/7749
#if NETCOREAPP3_0 || NETSTANDARD2_1
        private readonly IHostApplicationLifetime _applicationLifetime;
#else
        private readonly IApplicationLifetime _applicationLifetime;
#endif
        private readonly QueuedHostedServiceOptions _options;

        public QueuedHostedService(
            IBackgroundTaskQueue taskQueued,
            ILoggerFactory loggerFactory,
            BackgroundTaskContext context,
#if NETCOREAPP3_0 || NETSTANDARD2_1
            IHostApplicationLifetime applicationLifetime,
#else
            IApplicationLifetime applicationLifetime,
#endif
            IOptionsMonitor<QueuedHostedServiceOptions> options)
        {
            TaskQueued = taskQueued;
            _logger = loggerFactory.CreateLogger<QueuedHostedService>();
            _context = context;
            _options = options.CurrentValue;

#if NETCOREAPP3_0 || NETSTANDARD2_1
            _applicationLifetime = applicationLifetime;
            _applicationLifetime.ApplicationStopping.Register(OnApplicationStopping);
#else
            _applicationLifetime = applicationLifetime;
            _applicationLifetime.ApplicationStopping.Register(OnApplicationStopping);
#endif
        }

        public IBackgroundTaskQueue TaskQueued { get; }

        public override Task StartAsync(CancellationToken cancellationToken)
        {
            _logger.LogDebug("{ServiceName} is starting.", nameof(QueuedHostedService));

            return base.StartAsync(cancellationToken);
        }

        public override Task StopAsync(CancellationToken cancellationToken)
        {
            _logger.LogDebug("{ServiceName} is stopping.", nameof(QueuedHostedService));
            return base.StopAsync(cancellationToken);
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var (workItem, workItemName, onException) = await TaskQueued.DequeueAsync(stoppingToken);

                try
                {
                    await workItem(stoppingToken).ConfigureAwait(false);
                    _context.MarkAsComplete();
                }
                catch (Exception ex)
                {
                    var message = $"{nameof(QueuedHostedService)} encountered error while executing {workItemName} task.";

                    onException(new Exception(message, ex));

                    _logger.LogError(ex, message);
                }
            }
        }

        private void OnApplicationStopping()
        {
            if (_options.EnableApplicationOnStopWait)
            {
                _logger.LogDebug("{ServiceName} is entered {MethodName}.", nameof(QueuedHostedService), nameof(OnApplicationStopping));

                while (!_context.IsComplete)
                {
                    _logger.LogDebug(
                        "{ServiceName} is waiting: {Timespan} seconds for the number of tasks: {TaskCount} to complete.",
                        nameof(QueuedHostedService),
                        _options.ApplicationOnStopWaitTimeout.TotalSeconds,
                        _context.Count);

                    Thread.Sleep(_options.ApplicationOnStopWaitTimeout);
                }
            }
        }
    }
}
