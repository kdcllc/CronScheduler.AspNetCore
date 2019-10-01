using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.Extensions.StartupInitializer;

namespace CronScheduler.UnitTest
{
    public class TestStartupJob : IStartupJob
    {
        public async Task ExecuteAsync(CancellationToken cancellationToken = default)
        {
            await Task.Delay(TimeSpan.FromSeconds(10));

            await Task.CompletedTask;
        }
    }
}
