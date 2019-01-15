using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class StartupJobInitializer
    {
        private readonly ILogger<StartupJobInitializer> _logger;
        private readonly IEnumerable<IStartupJob> _startupJobs;

        public StartupJobInitializer(IEnumerable<IStartupJob> startupJobs, ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<StartupJobInitializer>();
            _startupJobs = startupJobs;
        }

        /// <summary>
        /// Starts jobs for all of the registered <see cref="IStartupJob"/> instances.
        /// </summary>
        /// <returns></returns>
        public async Task StartJobsAsync()
        {
            try
            {
                _logger.LogInformation("Starting startup jobs");

                foreach (var job in _startupJobs)
                {
                    try
                    {
                        await job.StartAsync();
                        _logger.LogInformation("{jobName} completed", job.GetType());
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError("{jobName} failed with the following message {message}", job.GetType(), ex.Message);
                        throw;
                    }
                }

                _logger.LogInformation("Startup jobs completed successfully", nameof(StartupJobInitializer));
            }
            catch (Exception ex)
            {
                _logger.LogError("{jobName} initialization failed with {ex}", nameof(StartupJobInitializer), ex.Message);
                throw;
            }
        }
    }
}
