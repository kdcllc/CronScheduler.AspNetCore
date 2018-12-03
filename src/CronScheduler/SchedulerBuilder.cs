using Microsoft.Extensions.DependencyInjection;
using System;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class SchedulerBuilder
    {
        public EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskExceptionHandler = null;

        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services;
        }

        public IServiceCollection Services { get; }
    }
}
