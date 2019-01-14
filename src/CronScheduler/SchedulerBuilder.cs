using Microsoft.Extensions.DependencyInjection;
using System;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class SchedulerBuilder
    {
        /// <summary>
        /// EventHanlder for Startup for Hosted Apps.
        /// </summary>
        public EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskExceptionHandler = null;

        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services;
        }

        /// <summary>
        /// <see cref="IServiceCollection"/> for the DI.
        /// </summary>
        public IServiceCollection Services { get; }
    }
}
