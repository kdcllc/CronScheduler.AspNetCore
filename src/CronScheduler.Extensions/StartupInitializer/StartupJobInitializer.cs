using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.Logging;

namespace CronScheduler.Extensions.StartupInitializer
{
    public class StartupJobInitializer
    {
        private readonly ILogger<StartupJobInitializer> _logger;
        private readonly IEnumerable<IStartupJob> _startupJobs;

        /// <summary>
        /// Initializes a new instance of the <see cref="StartupJobInitializer"/> class.
        /// </summary>
        /// <param name="startupJobs"></param>
        /// <param name="loggerFactory"></param>
        public StartupJobInitializer(IEnumerable<IStartupJob> startupJobs, ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<StartupJobInitializer>();

            _startupJobs = startupJobs;
        }

        /// <summary>
        /// Starts jobs for all of the registered <see cref="IStartupJob"/> instances.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public async Task StartJobsAsync(CancellationToken cancellationToken)
        {
            try
            {
                var jobCount = _startupJobs.ToList().Count;

                _logger.LogInformation("{name} start queuing {count} jobs", nameof(StartupJobInitializer), jobCount);

                foreach (var job in _startupJobs)
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    try
                    {
                        await job.ExecuteAsync(cancellationToken);
                        _logger.LogInformation("{jobName} completed", job.GetType());
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError("{jobName} failed with the following message {message}", job.GetType(), ex.Message);
                    }
                }

                _logger.LogInformation("{name} completed queuing {count} jobs", nameof(StartupJobInitializer), jobCount);
            }
            catch (Exception ex)
            {
                _logger.LogError("{name} initialization failed with {ex}", nameof(StartupJobInitializer), ex.Message);
                throw;
            }
        }
    }
}
