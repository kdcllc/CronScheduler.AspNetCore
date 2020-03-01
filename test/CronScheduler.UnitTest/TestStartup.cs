using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CronScheduler.UnitTest
{
    public class TestStartup
    {
        private readonly ILogger<TestStartup> _logger;

        public TestStartup(
            IConfiguration configuration,
            ILogger<TestStartup> logger)
        {
            Configuration = configuration;
            _logger = logger;
        }

        public IConfiguration Configuration { get; }

        public void ConfigureServices(IServiceCollection services)
        {
        }

        public void Configure(
            IApplicationBuilder app,
            IWebHostEnvironment env)
        {
            app.Map("/hc", route =>
            {
                route.Run(async context =>
                {
                    await context.Response.WriteAsync("healthy");
                });
            });
        }
    }
}
