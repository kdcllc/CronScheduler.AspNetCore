using System.Threading.Tasks;

using CronSchedulerApp.Data;
using CronSchedulerApp.Jobs;
using CronSchedulerApp.Services;

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using Polly;

namespace CronSchedulerApp
{
    public class Startup
    {
        private ILogger<Startup>? _logger;

        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            });

            services.AddDbContext<ApplicationDbContext>(options =>
            {
                if (Configuration["DatabaseProvider:Type"] == "Sqlite")
                {
                    options.UseSqlite(Configuration.GetConnectionString("SqliteConnection"));
                }

                if (Configuration["DatabaseProvider:Type"] == "SqlServer")
                {
                    options.UseSqlServer(Configuration.GetConnectionString("SqlConnection"));
                }
            });

            services.AddDefaultIdentity<IdentityUser>()
                .AddEntityFrameworkStores<ApplicationDbContext>();

            services.AddControllersWithViews();

            services.AddRazorPages();

            services.AddScheduler(builder =>
            {
                // 1. Add Torah Quote Service and Job.
                builder.Services.AddSingleton<TorahVerses>();

                // Build a policy that will handle exceptions, 408s, and 500s from the remote server
                builder.Services
                    .AddHttpClient<TorahService>()
                    .AddTransientHttpErrorPolicy(p => p.RetryAsync());

                builder.AddJob<TorahQuoteJob, TorahQuoteJobOptions>();

                // 2. Add User Service and Job
                builder.Services.AddScoped<UserService>();
                builder.AddJob<UserJob, UserJobOptions>();

                builder.UnobservedTaskExceptionHandler = UnobservedHandler;
            });

            // services.AddScheduler((sender, args) =>
            // {
            //    _logger.LogError(args.Exception.Message);
            //    args.SetObserved();
            // });
            services.AddBackgroundQueuedService(applicationOnStopWaitForTasksToComplete: true);
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env, ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<Startup>();

            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                app.UseDatabaseErrorPage();
            }
            else
            {
                app.UseExceptionHandler("/Home/Error");
                app.UseHsts();
            }

            app.UseHttpsRedirection();
            app.UseStaticFiles();
            app.UseCookiePolicy();

            app.UseAuthentication();

            app.UseRouting();

            // https://devblogs.microsoft.com/aspnet/blazor-now-in-official-preview/
            app.UseEndpoints(routes =>
            {
                routes.MapControllers();
                routes.MapDefaultControllerRoute();
                routes.MapRazorPages();
            });
        }

        private void UnobservedHandler(object sender, UnobservedTaskExceptionEventArgs args)
        {
            _logger?.LogError(args.Exception?.Message);
            args.SetObserved();
        }
    }
}
